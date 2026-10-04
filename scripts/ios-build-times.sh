#!/usr/bin/env bash
#
# Builds the app with the real iOS SDK (for the simulator, so nothing needs
# signing) and lists where the compiler spends its time: the slowest
# function bodies and expressions, and the build's own timing summary.
#
# Swift Playgrounds on an older iPad takes minutes over what a Mac does in
# seconds, and it runs out of memory on the same few functions. This is how
# those functions are found without an iPad. CI runs it on a macOS runner.
#
#   scripts/ios-build-times.sh            full build, report
#   KEEP_LOG=/path scripts/ios-build-times.sh   also keep the raw log
#   PER_FILE=1 scripts/ios-build-times.sh       one file per compile job, so
#                                               each file's own cost is listed
#   PATCH=<diff, gzipped, base64> ...           with a change applied first

set -uo pipefail
cd "$(dirname "$0")/.."

# A change to try without pushing it (the workflow's "patch" input): a
# unified diff from the repository root, gzipped and base64-encoded.
if [ -n "${PATCH:-}" ]; then
  echo "$PATCH" | base64 --decode | gunzip > /tmp/try.patch
  git apply --stat /tmp/try.patch
  git apply /tmp/try.patch || { echo "The patch does not apply."; exit 1; }
fi

app_dir="$(ls -d *.swiftpm | head -1)"
scheme="${SCHEME:-${app_dir%.swiftpm}}"
log="${KEEP_LOG:-/tmp/ios-build.log}"
derived="/tmp/ablox-derived"
rm -rf "$derived"

xcodebuild -version
cd "$app_dir"

# Xcode names the schemes after the package's products and targets, and the
# set changes with the targets. When the expected one is missing, build the
# app's own target instead, and say which schemes there were.
schemes="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/ { on = 1; next } on && NF { sub(/^[[:space:]]+/, ""); print }')"
if ! grep -qxF "$scheme" <<< "$schemes"; then
  echo "No scheme named \"$scheme\". The package has:"
  sed 's/^/  /' <<< "$schemes"
  app_target="$(grep -A1 -E '\.executableTarget\(' Package.swift | grep -oE 'name: "[^"]+"' | head -1 | cut -d'"' -f2)"
  if grep -qxF "$app_target" <<< "$schemes"; then scheme="$app_target"; else scheme="$(head -1 <<< "$schemes")"; fi
  echo "Building \"$scheme\"."
fi

stats="/tmp/ablox-stats"
rm -rf "$stats"; mkdir -p "$stats"
# Added to the package's own flags ($(inherited)), not in place of them.
flags="-Xfrontend -debug-time-function-bodies -Xfrontend -warn-long-expression-type-checking=150 -Xfrontend -stats-output-dir -Xfrontend $stats"
# Slower overall (every job reads every file), but the statistics then belong
# to one file each, code generation included.
batch="YES"
if [ -n "${PER_FILE:-}" ]; then batch="NO"; fi
if [ -n "${PER_FILE:-}" ]; then
  # Once without measuring, then clean: the system modules are then already
  # built, as on an iPad that has built before, and each file's time is its
  # own rather than whichever file first needed UIKit.
  xcodebuild build -scheme "$scheme" -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO > /dev/null 2>&1
  xcodebuild clean -scheme "$scheme" -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" > /dev/null 2>&1
fi
# Memory: every half second, the compilers running and how much each holds.
# An iPad with 3 GB stops a build that needs more, with no error shown.
memory="/tmp/ablox-memory.txt"
: > "$memory"
( while true; do
    ps -axo rss=,comm= | awk '/swift-frontend/ { n++; sum += $1; if ($1 > max) max = $1 } END { print n + 0, sum + 0, max + 0 }' >> "$memory"
    sleep 0.5
  done ) &
watcher=$!
start=$(date +%s)
xcodebuild build \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  -showBuildTimingSummary \
  ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_ENABLE_BATCH_MODE="$batch" \
  OTHER_SWIFT_FLAGS="\$(inherited) $flags" > "$log" 2>&1
status=$?
end=$(date +%s)
kill "$watcher" 2>/dev/null

echo
echo "== Build finished with status $status in $((end - start)) s"
awk '{ if ($1 > jobs) jobs = $1; if ($2 > total) total = $2; if ($3 > one) one = $3 }
     END { printf "== Memory: at most %d compilers at once, %d MB together, %d MB the largest one\n", jobs, total / 1024, one / 1024 }' "$memory"

echo
echo "== Slowest function bodies (ms, where, what)"
grep -E '^[0-9]+(\.[0-9]+)?ms[[:space:]]' "$log" \
  | sed "s|$PWD/||" \
  | sort -rn | awk -F'\t' '!seen[$2]++' | head -40 || true

echo
echo "== Time per file (sum of its function bodies, ms)"
grep -E '^[0-9]+(\.[0-9]+)?ms[[:space:]]' "$log" \
  | sed "s|$PWD/||" \
  | awk -F'\t' '!seen[$2]++ { split($2, where, ":"); ms = $1; sub(/ms$/, "", ms); total[where[1]] += ms }
                END { for (f in total) printf "%10.1f  %s\n", total[f], f }' \
  | sort -rn | head -30 || true

echo
echo "== Slow expressions"
grep -E "warning: expression took|warning: .* took [0-9]+ms to type-check" "$log" | sed "s|$PWD/||" | sort -u | head -60

echo
echo "== Compiler phases, summed over every compile job (seconds)"
python3 - "$stats" <<'PY'
import glob, json, sys, collections
total = collections.Counter()
jobs = 0
for path in glob.glob(sys.argv[1] + "/*.json"):
    try:
        data = json.load(open(path))
    except Exception:
        continue
    jobs += 1
    for key, value in data.items():
        if key.startswith("time.swift.") and key.endswith(".wall"):
            total[key[len("time.swift."):-len(".wall")]] += value
        if key.startswith("time.swift-frontend.") and key.endswith(".wall"):
            total["frontend " + key[len("time.swift-frontend."):-len(".wall")]] += value
print(f"{jobs} jobs")
for name, seconds in total.most_common(30):
    print(f"{seconds:9.2f}  {name}")
PY

if [ -n "${PER_FILE:-}" ]; then
echo
echo "== Cost per file, one compile job each (seconds: total = imports + checking + SILGen + IRGen + the rest, mostly LLVM)"
python3 - "$stats" <<'PY'
import glob, json, sys, collections
rows = []
modules = collections.Counter()
for path in glob.glob(sys.argv[1] + "/*.json"):
    try:
        data = json.load(open(path))
    except Exception:
        continue
    name = next((k[len("time.swift-frontend."):-len(".wall")] for k in data
                 if k.startswith("time.swift-frontend.") and k.endswith(".wall")), None)
    if not name:
        continue
    total = data["time.swift-frontend." + name + ".wall"]
    module, _, rest = name.partition("-")
    label = rest.split(".swift")[0] if ".swift" in rest else "(interface)"
    part = lambda key: data.get("time.swift." + key + ".wall", 0.0)
    imports, sema, silgen, irgen = part("parse-and-resolve-imports"), part("perform-sema"), part("SILGen"), part("IRGen")
    other = max(0.0, total - imports - sema - silgen - irgen)
    rows.append((total, module, label, imports, sema, silgen, irgen, other))
    modules[module] += total
print(f"{len(rows)} jobs; per module: " + ", ".join(f"{m} {t:.1f}" for m, t in modules.most_common()))
print(f"{'total':>7} {'import':>7} {'check':>7} {'SILGen':>7} {'IRGen':>7} {'rest':>7}  file")
for total, module, label, imports, sema, silgen, irgen, other in sorted(rows, reverse=True)[:60]:
    print(f"{total:7.2f} {imports:7.2f} {sema:7.2f} {silgen:7.2f} {irgen:7.2f} {other:7.2f}  {module}/{label}")
PY
fi

echo
echo "== Debug information on the Swift command lines (last flag wins), and all objects together"
grep -E 'swift-frontend|builtin-Swift|swiftc ' "$log" | grep -oE ' -g(none|line-tables-only|dwarf-types)?( |$)' | sort | uniq -c || true
find "$derived" -name '*.o' -path '*arm64*' -print0 2>/dev/null | xargs -0 stat -f '%z' 2>/dev/null \
  | awk '{ total += $1 } END { printf "%d KB in object files\n", total / 1024 }'

echo
echo "== Largest object files (KB, lines): the code each file turned into"
find "$derived" -name '*.o' -path '*arm64*' -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null | sort -rn | head -40 \
  | while read -r size path; do
      name="$(basename "$path" .o)"
      source="$(find . -name "$name.swift" | head -1)"
      lines="$( [ -n "$source" ] && wc -l < "$source" | tr -d ' ' || echo "?")"
      printf "%8d %6s  %s\n" $((size / 1024)) "$lines" "${source:-$name}"
    done

echo
echo "== What the code is: machine code by kind, over every object file of the app"
# Each function's size is the distance to the next symbol in __text, and its
# name, demangled, says what made it: a closure, a type's metadata, copying a
# value, a key path... SwiftUI turns a little source into a lot of these.
objects="$(find "$derived" -name '*.o' -path '*arm64*' 2>/dev/null)"
if [ -n "$objects" ]; then
  python3 - $objects <<'PY'
import subprocess, sys, re, collections
kinds = collections.Counter(); counts = collections.Counter(); biggest = []
per_file = collections.defaultdict(collections.Counter)
def kind(name):
    rules = [
        ("closure", r"^closure #|^implicit closure #|in closure #"),
        ("metadata", r"type metadata|metadata completion|metadata instantiation|metadata pattern|nominal type descriptor"),
        ("outlined value ops", r"^outlined "),
        ("value witnesses", r"value witness|^initializeWithCopy|^initializeWithTake|^assignWithCopy|^assignWithTake|^destroy for|^getEnumTag|^storeEnumTag|^destructiveProjectEnumData|^destructiveInjectEnumTag|^initializeBufferWithCopyOfBuffer"),
        ("key paths", r"key path"),
        ("witness tables", r"witness table accessor|associated conformance|associated type"),
        ("protocol witnesses", r"^protocol witness for"),
        ("thunks", r"thunk"),
        ("view bodies", r"\.body\.getter"),
        ("accessors", r"\.getter|\.setter|\.modify|\.read|\.unsafeMutableAddressor|\.didset|\.willset"),
        ("initializers", r"variable initialization expression|\.init\(|default argument"),
        ("Codable", r"CodingKeys|Encodable|Decodable|encode\(to:|init\(from:"),
    ]
    for label, pattern in rules:
        if re.search(pattern, name):
            return label
    return "other functions"
for path in sys.argv[1:]:
    try:
        out = subprocess.run(["xcrun", "nm", "-n", "-m", "--defined-only", path], capture_output=True, text=True).stdout
    except Exception:
        continue
    syms = []
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]+) \(__TEXT,__text\) (?:non-)?external (?:\[[^\]]*\] )?(\S+)", line)
        if m:
            syms.append((int(m.group(1), 16), m.group(2)))
    if len(syms) < 2:
        continue
    names = [n for _, n in syms]
    demangled = subprocess.run(["xcrun", "swift-demangle", "--simplified", "--compact"], input="\n".join(names),
                               capture_output=True, text=True).stdout.splitlines()
    if len(demangled) != len(names):
        demangled = names
    file = path.rsplit("/", 1)[-1][:-2]
    for i in range(len(syms) - 1):
        size = syms[i + 1][0] - syms[i][0]
        k = kind(demangled[i])
        kinds[k] += size; counts[k] += 1; per_file[file][k] += size
        biggest.append((size, file, demangled[i][:150]))
total = sum(kinds.values()) or 1
print(f"{total // 1024} KB of functions in {sum(counts.values())} functions")
print(f"{'KB':>8} {'share':>6} {'count':>7}  kind")
for k, size in kinds.most_common():
    print(f"{size // 1024:8d} {100.0 * size / total:5.1f}% {counts[k]:7d}  {k}")
print("-- Largest functions")
for size, file, name in sorted(biggest, reverse=True)[:40]:
    print(f"{size // 1024:6d} KB  {file}: {name}")
print("-- The biggest files by kind (KB)")
for file, c in sorted(per_file.items(), key=lambda kv: -sum(kv[1].values()))[:12]:
    print(f"{sum(c.values()) // 1024:6d}  {file}: " + ", ".join(f"{k} {v // 1024}" for k, v in c.most_common(5)))
PY
fi

echo
echo "== What an update rebuilds: the files compiled again after a change to what one file declares"
# From the compiler's own dependency records (.swiftdeps), turned into text
# by swift-frontend run under the name swift-dependency-tool, which is how it
# picks that mode.
frontend="$(xcrun --find swift-frontend 2>/dev/null || true)"
if [ -n "$frontend" ]; then
  deps_dir="$(mktemp -d)"
  ln -s "$frontend" "$deps_dir/swift-dependency-tool"
  find "$derived" -name '*.swiftdeps' -path '*arm64*' ! -name '*-master*' 2>/dev/null | while read -r deps; do
    "$deps_dir/swift-dependency-tool" --to-yaml --input-filename="$deps" \
      --output-filename="$deps_dir/$(basename "$deps").yaml" > /dev/null 2>&1
  done
  python3 ../scripts/swiftdeps-fanin.py Sources "$deps_dir"/*.yaml 2>&1 | head -45
else
  echo "swift-frontend not found"
fi

echo
echo "== Build timing summary"
sed -n '/Build Timing Summary/,/^\*\* BUILD/p' "$log" | head -60

echo
echo "== Errors"
grep -E "error:" "$log" | sed "s|$PWD/||" | sort -u | head -400

exit $status
