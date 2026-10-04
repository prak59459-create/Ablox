#!/usr/bin/env bash
#
# Starts the app on an iPad simulator and watches it, so a crash at launch
# says where it happened. Swift Playgrounds only reports "Ablox may have
# crashed"; this prints what the app wrote (a Swift crash names its reason
# on stderr), the crash report with the crashing thread, the app's own log
# lines, and a screenshot, and fails when the app did not stay running.
#
#   scripts/ios-launch-check.sh            fresh install, watch 30 s
#   WATCH=60 scripts/ios-launch-check.sh   watch longer
#
# CI runs it on a macOS runner (.github/workflows/launch-check.yml).

set -uo pipefail
cd "$(dirname "$0")/.."

app_dir="$(ls -d *.swiftpm | head -1)"
scheme="${SCHEME:-${app_dir%.swiftpm}}"
derived="/tmp/ablox-launch-derived"
out="${OUT:-/tmp/ablox-launch}"
watch="${WATCH:-30}"
rm -rf "$derived" "$out"
mkdir -p "$out"

xcodebuild -version

# The newest iPad simulator there is.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
chosen = ""
for runtime in sorted(devices, key=lambda r: [int(p) for p in r.rsplit("iOS-", 1)[-1].split("-") if p.isdigit()] if "iOS" in r else [0]):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if "iPad" in device["name"]:
            chosen = device["udid"]
print(chosen)')"
if [ -z "$udid" ]; then
  echo "No iPad simulator available."
  xcrun simctl list devices available
  exit 1
fi
echo "== Simulator: $(xcrun simctl list devices | grep "$udid")"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 || true

cd "$app_dir"
schemes="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/ { on = 1; next } on && NF { sub(/^[[:space:]]+/, ""); print }')"
if ! grep -qxF "$scheme" <<< "$schemes"; then
  app_target="$(grep -A1 -E '\.executableTarget\(' Package.swift | grep -oE 'name: "[^"]+"' | head -1 | cut -d'"' -f2)"
  if grep -qxF "$app_target" <<< "$schemes"; then scheme="$app_target"; else scheme="$(head -1 <<< "$schemes")"; fi
fi
echo "== Building \"$scheme\" for the simulator"
if ! xcodebuild build -scheme "$scheme" -destination "id=$udid" -derivedDataPath "$derived" \
     CODE_SIGNING_ALLOWED=NO > "$out/build.log" 2>&1; then
  echo "The build failed:"
  grep -E "error:" "$out/build.log" | head -40
  tail -30 "$out/build.log"
  exit 1
fi
cd ..

app="$(find "$derived/Build/Products" -maxdepth 2 -name "*.app" -type d | head -1)"
if [ -z "$app" ]; then
  echo "No .app was built."
  find "$derived/Build/Products" -maxdepth 3 | head -40
  exit 1
fi
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
echo "== Installing $app ($bundle)"
xcrun simctl install "$udid" "$app"

# Starts the app with its output written to files. The simulator now and
# then does not answer a launch (no process number comes back); that is
# the simulator, not the app, so it is tried again, three times at most.
launch() {
  local name="$1"; shift
  local attempt
  for attempt in 1 2 3; do
    xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
    if perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl launch --terminate-running-process \
         --stdout="$out/$name.stdout.log" --stderr="$out/$name.stderr.log" \
         "$udid" "$bundle" ${@+"$@"} > "$out/$name.launch.log" 2>&1 \
       && grep -qE ": [0-9]+" "$out/$name.launch.log"; then
      return 0
    fi
    echo "   (the simulator did not start the app, attempt $attempt: $(tr '\n' ' ' < "$out/$name.launch.log"))"
    sleep 5
  done
  return 1
}

is_running() {
  xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -F "UIKitApplication:$bundle" | awk '{ print $1 }' | grep -qE '^[0-9]+$'
}

touch "$out/started"
sleep 1
echo "== Launching and watching for $watch seconds"
if ! launch main; then
  echo "== The simulator would not start the app at all (not a crash of the app)."
  exit 1
fi
sleep "$watch"
xcrun simctl io "$udid" screenshot "$out/screen.png" > /dev/null 2>&1 || true

running=0
if is_running; then running=1; fi

echo
echo "== What the app wrote (stdout and stderr)"
cat "$out/main.launch.log"
cat "$out/main.stdout.log" "$out/main.stderr.log" 2>/dev/null | tail -200

echo
echo "== The app's log lines"
xcrun simctl spawn "$udid" log show --last 3m --style compact \
  --predicate "process == \"$executable\" AND (messageType == error OR messageType == fault OR eventMessage CONTAINS[c] \"fatal\" OR eventMessage CONTAINS[c] \"crash\")" \
  2>/dev/null | tail -120 > "$out/log.txt" || true
cat "$out/log.txt"

echo
echo "== Crash reports"
found=0
for report in $(find "$HOME/Library/Logs/DiagnosticReports" -newer "$out/started" -type f \( -name "*.ips" -o -name "*.crash" \) 2>/dev/null); do
  if grep -q "$executable" "$report"; then
    found=1
    cp "$report" "$out/"
    echo "-- $report"
    python3 - "$report" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
parts = text.split("\n", 1)
try:
    body = json.loads(parts[1])
except Exception:
    print(text[:6000])
    sys.exit()
exc = body.get("exception", {})
print("exception:", exc)
print("termination:", body.get("termination", {}))
asi = body.get("asi")
if asi:
    print("asi:", json.dumps(asi)[:3000])
images = body.get("usedImages", [])
threads = body.get("threads", [])
for t in threads:
    if not t.get("triggered"):
        continue
    print("crashed thread:", t.get("name", ""), t.get("queue", ""))
    for f in t.get("frames", [])[:60]:
        image = images[f.get("imageIndex", 0)] if f.get("imageIndex", 0) < len(images) else {}
        name = image.get("name", "?")
        symbol = f.get("symbol", "")
        loc = ""
        if "sourceFile" in f:
            loc = f" ({f['sourceFile']}:{f.get('sourceLine', '?')})"
        print(f"  {name:28} {symbol}{loc}")
PY
  fi
done
[ "$found" = 0 ] && echo "(none)"

echo
if [ "$running" = 1 ]; then
  echo "== The app is still running after $watch seconds."
else
  echo "== The app is NOT running after $watch seconds: it crashed or quit at launch."
  exit 1
fi

# Each tab opened straight away (launch argument AbloxOpenTab), so a crash
# in any tab's first screen shows here too, not only the Play tab's.
failed=""
for tab in ${TABS-Games Worlds Avatar Shop Settings}; do
  touch "$out/started-$tab"
  if ! launch "$tab" -AbloxOpenTab "$tab"; then
    echo "== $tab: the simulator would not start the app (not a crash of the app)"
    failed="$failed $tab"
    continue
  fi
  sleep "${TAB_WATCH:-12}"
  xcrun simctl io "$udid" screenshot "$out/screen-$tab.png" > /dev/null 2>&1 || true
  if is_running; then
    echo "== $tab: still running"
  else
    echo "== $tab: NOT running"
    failed="$failed $tab"
    cat "$out/$tab.stdout.log" "$out/$tab.stderr.log" 2>/dev/null | grep -iE "fatal|error|crash|precondition" | tail -20
    for report in $(find "$HOME/Library/Logs/DiagnosticReports" -newer "$out/started-$tab" -type f -name "*.ips" 2>/dev/null); do
      grep -q "$executable" "$report" || continue
      python3 - "$report" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text.split("\n", 1)[1])
images = body.get("usedImages", [])
for t in body.get("threads", []):
    if t.get("triggered"):
        for f in t.get("frames", [])[:25]:
            i = f.get("imageIndex", 0)
            print("   ", images[i].get("name", "?") if i < len(images) else "?", f.get("symbol", ""))
PY
    done
  fi
done

# The frame-rate run: straight into a busy world (RenderBenchmark: about
# 3,000 parts and 60 walking characters), which prints a line a second of
# how fast it draws, at what level, and how many parts merged meshes draw.
# A simulator's numbers are not an iPad's; a crash here is a crash anywhere.
if [ "${BENCHMARK:-1}" = 1 ]; then
  touch "$out/started-benchmark"
  if launch benchmark -AbloxPlayBenchmark YES; then
    # Where the time goes, from the inside: macOS's sampler on the app while
    # it draws merged meshes on High (seconds 26 to 34 of the run).
    sleep "${BENCHMARK_SAMPLE_AT:-26}"
    pid="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -F "UIKitApplication:$bundle" | awk '{ print $1 }' | head -1)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      sample "$pid" 8 -mayDie -file "$out/benchmark-sample.txt" > "$out/benchmark-sample.log" 2>&1 || true
    else
      echo "   (no process to sample: \"$pid\")" > "$out/benchmark-sample.log"
    fi
    sleep "${BENCHMARK_REST:-66}"
    xcrun simctl io "$udid" screenshot "$out/screen-benchmark.png" > /dev/null 2>&1 || true
    echo "== Frame rate in the benchmark world"
    lines="$(grep -hE "AbloxFPS|AbloxShapes" "$out/benchmark.stderr.log" "$out/benchmark.stdout.log" 2>/dev/null)"
    # The first 80 seconds (merged, part by part, Auto settling), then the
    # end: the sky alone, the most this simulator draws at all.
    head -84 <<< "$lines"
    echo "   ..."
    tail -12 <<< "$lines"
    echo "== Players in every kind of gear, and their merged parts"
    grep -h "AbloxCrowd" "$out/benchmark.stderr.log" "$out/benchmark.stdout.log" 2>/dev/null \
      || echo "   (no players were dressed)"
    echo "== The same view merged, merged again and part by part (nothing moving)"
    grep -h "AbloxLook" "$out/benchmark.stderr.log" "$out/benchmark.stdout.log" 2>/dev/null \
      || echo "   (no comparison was made)"
    grep -q "AbloxFPS" "$out/benchmark.stderr.log" "$out/benchmark.stdout.log" 2>/dev/null \
      || echo "   (no frame-rate lines: the game did not start drawing)"
    if [ ! -s "$out/benchmark-sample.txt" ]; then
      echo "== The sampler wrote nothing:"
      tail -5 "$out/benchmark-sample.log" 2>/dev/null
    fi
    if [ -s "$out/benchmark-sample.txt" ]; then
      echo "== Where the time went (8 s sampled while drawing merged meshes)"
      python3 - "$out/benchmark-sample.txt" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
top = text.split("Sort by top of stack, same collapsed (when >= 5):")
if len(top) > 1:
    print("-- On top of the stack (self time), all threads:")
    for line in top[1].strip().splitlines()[:30]:
        print("  ", line.strip()[:170])
# The main thread (the first in the call graph): its own time by library
# and by function (each frame's samples less its children's), then the
# heaviest frames a few levels down.
graph = text.split("Call graph:")
if len(graph) > 1:
    rows = []
    for line in graph[1].split("\n"):
        m = re.match(r"^([\s+!:|]*)(\d+)\s+(.*)$", line)
        if m:
            rows.append((len(m.group(1)), int(m.group(2)), m.group(3)))
        elif rows and not line.strip():
            break
    if rows:
        top_depth = rows[0][0]
        main = [rows[0]]
        for row in rows[1:]:
            if row[0] <= top_depth:
                break
            main.append(row)
        total = max(main[0][1], 1)
        own, by_library = {}, {}
        for i, (depth, count, name) in enumerate(main):
            children, next_depth = 0, None
            for depth2, count2, _ in main[i + 1:]:
                if depth2 <= depth:
                    break
                if next_depth is None:
                    next_depth = depth2
                if depth2 == next_depth:
                    children += count2
            mine = max(0, count - children)
            if not mine:
                continue
            fn = re.sub(r"\s+\+ \d+.*$", "", name).strip()
            found = re.search(r"\(in ([^)]+)\)", name)
            lib = found.group(1) if found else "?"
            own[fn] = own.get(fn, 0) + mine
            by_library[lib] = by_library.get(lib, 0) + mine
        print("-- Main thread: %d samples. Its own time by library:" % total)
        for lib, count in sorted(by_library.items(), key=lambda kv: -kv[1])[:14]:
            print("   %5.1f%%  %s" % (100.0 * count / total, lib))
        print("-- Main thread: functions by their own time:")
        for fn, count in sorted(own.items(), key=lambda kv: -kv[1])[:40]:
            print("   %5.1f%%  %s" % (100.0 * count / total, fn[:150]))
        print("-- Inside the game's own frame (tick), 1% of the main thread or more:")
        shown = 0
        for i, (depth, count, name) in enumerate(main):
            if "Coordinator.tick(deltaTime:)" not in name:
                continue
            print("   %5.1f%% %s" % (100.0 * count / total, name[:140]))
            for depth2, count2, name2 in main[i + 1:]:
                if depth2 <= depth:
                    break
                if count2 * 100 >= total and depth2 - depth <= 30 and shown < 90:
                    print("   %5.1f%% %s%s" % (100.0 * count2 / total, " " * ((depth2 - depth) // 2), name2[:140]))
                    shown += 1
        print("-- Main thread: heaviest frames (3% or more), a few levels down:")
        shown = 0
        for depth, count, name in main:
            if count * 100 >= 3 * total and depth - top_depth <= 80:
                print("   %5.1f%% %s%s" % (100.0 * count / total, " " * ((depth - top_depth) // 2), name[:140]))
                shown += 1
                if shown >= 120:
                    break
PY
    fi
    if is_running; then
      echo "== Benchmark: still running"
    else
      echo "== Benchmark: NOT running"
      failed="$failed benchmark"
      cat "$out/benchmark.stdout.log" "$out/benchmark.stderr.log" 2>/dev/null | grep -iE "fatal|error|crash|precondition" | tail -20
      for report in $(find "$HOME/Library/Logs/DiagnosticReports" -newer "$out/started-benchmark" -type f -name "*.ips" 2>/dev/null); do
        grep -q "$executable" "$report" || continue
        cp "$report" "$out/"
        python3 - "$report" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text.split("\n", 1)[1])
print("exception:", body.get("exception", {}))
images = body.get("usedImages", [])
for t in body.get("threads", []):
    if t.get("triggered"):
        for f in t.get("frames", [])[:40]:
            i = f.get("imageIndex", 0)
            loc = f" ({f['sourceFile']}:{f.get('sourceLine', '?')})" if "sourceFile" in f else ""
            print("   ", images[i].get("name", "?") if i < len(images) else "?", f.get("symbol", ""), loc)
PY
      done
    fi
  else
    echo "== Benchmark: the simulator would not start the app (not a crash of the app)"
  fi
fi

if [ -n "$failed" ]; then
  echo "== Runs that stopped the app:$failed"
  exit 1
fi
if [ -n "${TABS-x}" ]; then echo "== Every tab opened without stopping the app."; fi
