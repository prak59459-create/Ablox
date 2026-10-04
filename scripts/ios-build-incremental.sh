#!/usr/bin/env bash
#
# How long a build takes after a small change, the way an iPad builds after
# Settings → Updates has written only the files that changed into the project
# already there: a full build first, then one rebuild after each kind of
# change, timed separately.
#
#   scripts/ios-build-incremental.sh
#
# The changes tried, each undone before the next:
#   nothing          a build with nothing changed (the floor)
#   version          the version and build numbers, as every release changes them
#   ui-body          the inside of one screen's body
#   engine-body      the inside of one function in the 3D engine
#   core-new-private a new private function in AbloxCore
#   core-leaf-private the same in an AbloxCore file few others use
#   menu … script-api the same in each of the files updates touch most
#                    (the main menu, the settings, the play screen, the 3D
#                    view, the session, blocks, players, the script API)
#   core-interface   a new public function in AbloxCore (its interface changes)
#   core-body-edit   a number inside an existing AbloxCore function, nothing else
#   core-string      one more translation in Strings.swift, as features add them
#   core-touch       an AbloxCore file saved again unchanged
#
# CI runs it from Actions with the "incremental" input.

set -uo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

# A change to try first, as in ios-build-times.sh: a build flag in
# Package.swift, say, to see what it does to rebuilds.
if [ -n "${PATCH:-}" ]; then
  echo "$PATCH" | base64 --decode | gunzip > /tmp/try.patch
  git apply --stat /tmp/try.patch
  git apply /tmp/try.patch || { echo "The patch does not apply."; exit 1; }
fi

app_dir="$(ls -d *.swiftpm | head -1)"
scheme="${SCHEME:-${app_dir%.swiftpm}}"
derived="/tmp/ablox-incremental"
rm -rf "$derived"

xcodebuild -version
cd "$app_dir"

schemes="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/ { on = 1; next } on && NF { sub(/^[[:space:]]+/, ""); print }')"
if ! grep -qxF "$scheme" <<< "$schemes"; then
  app_target="$(grep -A1 -E '\.executableTarget\(' Package.swift | grep -oE 'name: "[^"]+"' | head -1 | cut -d'"' -f2)"
  if grep -qxF "$app_target" <<< "$schemes"; then scheme="$app_target"; else scheme="$(head -1 <<< "$schemes")"; fi
fi

build() {
  local label="$1"
  local log="/tmp/incremental-$label.log"
  local start end status
  start=$(date +%s)
  xcodebuild build \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" \
    -showBuildTimingSummary \
    ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO > "$log" 2>&1
  status=$?
  end=$(date +%s)
  local swift
  swift="$(grep -E '^SwiftCompile \([0-9]+ tasks?\) \|' "$log" | sed 's/.*| //')"
  # The Swift files compiled again: each is a path on a SwiftCompile line.
  local files
  files="$(grep -E '^SwiftCompile normal' "$log" | grep -oE '/[^ ]+\.swift' | sort -u | wc -l | tr -d ' ')"
  printf "%-16s status %s  %4d s   Swift compiling %s, %s files\n" "$label" "$status" $((end - start)) "${swift:-none}" "$files"
  [ "$status" -eq 0 ] || grep -E "error:" "$log" | sort -u | head -20
  # With `-driver-show-incremental` in the patch, the driver says why it
  # compiled each file again; the first few reasons, with paths shortened.
  grep -E 'remark: Incremental compilation' "$log" | sed -E 's|/[^ ]*/Sources/|Sources/|g; s|.*remark: Incremental compilation: ||' \
    | grep -vE '^(Skipping|Enabling|Incremental compilation has been)' | sort | uniq -c | sort -rn | head -12 | sed 's/^/      /' || true
  # Where the rest of the time went: what a rebuild of a few files costs
  # whatever they are (writing the module's summary, linking, the icons).
  if [ "$label" != first ]; then
    sed -n '/Build Timing Summary/,/^\*\* BUILD/p' "$log" | grep -E '\| [0-9.]+ seconds' | grep -v '^SwiftCompile ' \
      | sort -t'|' -k2 -rn | head -4 | sed -E 's/ \(([0-9]+) tasks?\) \| ([0-9.]+) seconds/ \2 s/' | paste -sd ',' - | sed 's/^/      also: /;s/,/, /g' || true
  fi
}

# Appends a line to a file, builds, and puts the file back.
try() {
  local label="$1" file="$2" line="$3"
  # A name of its own for each probe, so one probe's leftovers in the
  # compiler's records are not mistaken for a use by the next.
  line="${line//incrementalProbe/incrementalProbe_${label//-/_}}"
  cp "$file" /tmp/incremental-backup
  printf '%s\n' "$line" >> "$file"
  build "$label"
  cp /tmp/incremental-backup "$file"
  # Back to where it was, so each change is measured on its own.
  build "$label-undo" > /dev/null
}

echo
echo "== A full build, then one rebuild after each change"
build first
build again
build nothing

cp Package.swift /tmp/incremental-manifest
cp Sources/AppRelease.swift /tmp/incremental-release
sed -i '' -E 's/displayVersion: "[^"]*"/displayVersion: "99.9"/; s/bundleVersion: "[^"]*"/bundleVersion: "999"/' Package.swift
sed -i '' -E 's/static let version = "[^"]*"/static let version = "99.9"/; s/static let build = [0-9]+/static let build = 999/' Sources/AppRelease.swift
build version
cp /tmp/incremental-manifest Package.swift
cp /tmp/incremental-release Sources/AppRelease.swift
build version-undo > /dev/null

# Lines added at the end of a file change one thing only: a function body, or
# a new public declaration.
try ui-body Sources/UI/MainMenu/ShopView.swift 'private func incrementalProbe() -> Int { 1 }'
try engine-body Sources/Engine/RigidParts.swift 'private func incrementalProbe() -> Int { 1 }'
try core-new-private Sources/AbloxCore/BlockAnimation.swift 'private func incrementalProbe() -> Int { 1 }'
try core-leaf-private Sources/AbloxCore/ZipArchive.swift 'private func incrementalProbe() -> Int { 1 }'
try core-interface Sources/AbloxCore/BlockAnimation.swift 'public func incrementalProbe() -> Int { 1 }'

# The files updates touch most often, each with a new private function: how
# many files a typical update rebuilds through them.
try menu Sources/UI/MainMenu/MainMenuView.swift 'private func incrementalProbe() -> Int { 1 }'
try settings Sources/UI/AppSettings.swift 'private func incrementalProbe() -> Int { 1 }'
try play-screen Sources/UI/Game/PlayScreen.swift 'private func incrementalProbe() -> Int { 1 }'
try viewport Sources/Engine/GameViewport.swift 'private func incrementalProbe() -> Int { 1 }'
try session Sources/Net/SessionCoordinator.swift 'private func incrementalProbe() -> Int { 1 }'
try blocks Sources/AbloxCore/BlockData.swift 'private func incrementalProbe() -> Int { 1 }'
try player Sources/AbloxCore/Player.swift 'private func incrementalProbe() -> Int { 1 }'
try script-api Sources/AbloxCore/GameRuntimeAPI.swift 'private func incrementalProbe() -> Int { 1 }'

# Changes inside what is already there, done with sed and undone by copying
# the file back.
edit() {
  local label="$1" file="$2" expression="$3"
  cp "$file" /tmp/incremental-backup
  sed -i '' -E "$expression" "$file"
  if cmp -s "$file" /tmp/incremental-backup; then echo "$label: the edit changed nothing"; return; fi
  build "$label"
  cp /tmp/incremental-backup "$file"
  build "$label-undo" > /dev/null
}
edit core-body-edit Sources/AbloxCore/BlockAnimation.swift 's/sin\(t \* 2\.4\) \* 10/sin(t * 2.4) * 11/'
edit core-string Sources/AbloxCore/Strings.swift 's/\("Match the iPad", "iPadに合わせる"\),/("Match the iPad", "iPadに合わせる"), ("Incremental probe", "テスト"),/'
touch Sources/AbloxCore/BlockAnimation.swift
build core-touch
