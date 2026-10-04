#!/usr/bin/env bash
#
# What one build setting is worth: builds the app several times in one go,
# alternating with and without the setting, over the same warm module cache
# (as on an iPad that has built before). Runner speed varies a lot from job
# to job, so only builds in the same job are compared.
#
#   COMPARE="GCC_GENERATE_DEBUGGING_SYMBOLS=NO" scripts/ios-build-compare.sh
#   PATCH=<unified diff, gzipped, base64> scripts/ios-build-compare.sh
#
# With PATCH, the changed builds have that change applied to the source (a
# different way of writing something, a flag in Package.swift), so a change
# can be measured before it is pushed. REPEATS sets how many pairs of
# builds; the runner's speed wanders by a fifth from build to build, so the
# means over several pairs are what to read.
#
# CI runs it from Actions with the "compare" or "patch" input filled in.

set -uo pipefail
cd "$(dirname "$0")/.."

app_dir="$(ls -d *.swiftpm | head -1)"
scheme="${SCHEME:-${app_dir%.swiftpm}}"
derived="/tmp/ablox-compare"
read -r -a changed <<< "${COMPARE:-}"
if [ ${#changed[@]} -eq 0 ] && [ -z "${PATCH:-}" ]; then
  echo "set COMPARE to build settings to try, or PATCH to a change" >&2
  exit 2
fi
repeats="${REPEATS:-2}"
patch=""
if [ -n "${PATCH:-}" ]; then
  patch="/tmp/try.patch"
  echo "$PATCH" | base64 --decode | gunzip > "$patch"
  git apply --stat "$patch"
  git apply --check "$patch" || { echo "The patch does not apply."; exit 1; }
fi
root="$PWD"
rm -rf "$derived"

xcodebuild -version
cd "$app_dir"

schemes="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/ { on = 1; next } on && NF { sub(/^[[:space:]]+/, ""); print }')"
if ! grep -qxF "$scheme" <<< "$schemes"; then
  app_target="$(grep -A1 -E '\.executableTarget\(' Package.swift | grep -oE 'name: "[^"]+"' | head -1 | cut -d'"' -f2)"
  if grep -qxF "$app_target" <<< "$schemes"; then scheme="$app_target"; else scheme="$(head -1 <<< "$schemes")"; fi
fi

results="/tmp/compare-results.txt"
: > "$results"

build() {
  local label="$1"; shift
  local log="/tmp/compare-$label.log"
  xcodebuild clean -scheme "$scheme" -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" > /dev/null 2>&1
  local start end status
  start=$(date +%s)
  xcodebuild build \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" \
    -showBuildTimingSummary \
    ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    "$@" > "$log" 2>&1
  status=$?
  end=$(date +%s)
  local swift emit
  swift="$(grep -E '^SwiftCompile \([0-9]+ tasks?\) \|' "$log" | sed 's/.*| //')"
  emit="$(grep -E '^SwiftEmitModule \([0-9]+ tasks?\) \|' "$log" | sed 's/.*| //')"
  local objects
  objects="$(find "$derived" -name '*.o' -path '*arm64*' -print0 2>/dev/null | xargs -0 stat -f '%z' 2>/dev/null \
    | awk '{ total += $1 } END { printf "%d", total / 1024 }')"
  printf "%-14s status %s  %4d s   Swift compiling %s   interfaces %s   objects %s KB\n" \
    "$label" "$status" $((end - start)) "${swift:-?}" "${emit:-?}" "${objects:-?}"
  echo "$label $((end - start)) ${swift%% *}" >> "$results"
  [ "$status" -eq 0 ] || grep -E "error:" "$log" | sort -u | head -20
}

with_patch() { [ -z "$patch" ] || (cd "$root" && git apply "$patch"); }
without_patch() { [ -z "$patch" ] || (cd "$root" && git apply -R "$patch"); }

echo
echo "== Comparing: ${changed[*]:-}${patch:+ (with the patch)}, $repeats pairs"
build warm-up
for i in $(seq 1 "$repeats"); do
  build plain
  with_patch
  # (Written so bash 3.2, macOS's, accepts an empty list under set -u.)
  build changed ${changed[@]+"${changed[@]}"}
  without_patch
done

echo
echo "== Means over $repeats pairs (seconds of wall time, seconds of Swift compiling)"
awk '$1 != "warm-up" { n[$1]++; wall[$1] += $2; cpu[$1] += $3 }
     END { for (k in n) printf "%-8s wall %6.1f   compiling %6.1f\n", k, wall[k] / n[k], cpu[k] / n[k] }' "$results"
