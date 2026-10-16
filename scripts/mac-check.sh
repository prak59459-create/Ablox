#!/usr/bin/env bash
#
# Ablox on a Mac, as an iPad app ("Designed for iPad" on Apple silicon):
# lists where the package can be built, builds it for the Mac, starts it and
# takes a screenshot, printing what the app wrote. CI runs it on a macOS
# runner (.github/workflows/mac-check.yml).
#
#   scripts/mac-check.sh             build, start, watch 30 s
#   WATCH=60 scripts/mac-check.sh

set -uo pipefail
cd "$(dirname "$0")/.."

app_dir="$(ls -d *.swiftpm | head -1)"
scheme="${SCHEME:-${app_dir%.swiftpm}}"
derived="/tmp/ablox-mac-derived"
out="${OUT:-/tmp/ablox-mac}"
watch="${WATCH:-30}"
rm -rf "$derived" "$out"
mkdir -p "$out"

xcodebuild -version
uname -m
sw_vers

# The names AppleProductTypes really has (capabilities, device families):
# a wrong guess in Package.swift stops the project opening on an iPad, so
# they are read here before they are used.
echo "== AppleProductTypes"
interface="$(find "$(xcode-select -p)/.." -name 'AppleProductTypes.swiftinterface' -path '*arm64*' 2>/dev/null | head -1)"
[ -n "$interface" ] || interface="$(find "$(xcode-select -p)/.." -name '*.swiftinterface' -path '*AppleProductTypes*' 2>/dev/null | head -1)"
echo "$interface"
if [ -n "$interface" ]; then
  cp "$interface" "$out/AppleProductTypes.swiftinterface"
  grep -nE "case [a-zA-Z]+|static (func|var|let) [a-zA-Z]+" "$interface" | grep -iE "bluetooth|mac|pad|phone|network|connection|family|capabilit" | head -60
fi

cd "$app_dir"
echo "== Where it can be built"
xcodebuild -showdestinations -scheme "$scheme" 2>&1 | tee "$out/destinations.txt" | sed -n '1,40p'

# "Designed for iPad" first; Mac Catalyst if the package ever offers it.
built=""
for destination in "platform=macOS,arch=arm64,variant=Designed for iPad" "platform=macOS,variant=Designed for iPad" "platform=macOS,variant=Mac Catalyst"; do
  echo "== Building for: $destination"
  if xcodebuild build -scheme "$scheme" -destination "$destination" -derivedDataPath "$derived" \
       CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
       > "$out/build.log" 2>&1; then
    built="$destination"
    break
  fi
  echo "That did not build:"
  grep -E "error:" "$out/build.log" | head -15
done
if [ -z "$built" ]; then
  tail -40 "$out/build.log"
  exit 1
fi
echo "== Built for $built"

app="$(find "$derived/Build/Products" -maxdepth 3 -name '*.app' -type d | head -1)"
echo "== App: $app"
[ -n "$app" ] || exit 1
ls "$derived/Build/Products"
codesign -dv "$app" 2>&1 | head -5 || true

echo "== Starting it"
log_start="$(date '+%Y-%m-%d %H:%M:%S')"
open "$app" > "$out/open.txt" 2>&1
cat "$out/open.txt"
sleep "$watch"

name="$(basename "$app" .app)"
if pgrep -fl "$name" > "$out/process.txt"; then
  echo "== Running after ${watch} s:"
  cat "$out/process.txt"
  status=0
else
  echo "== Not running after ${watch} s"
  status=1
fi
screencapture -x "$out/screen.png" 2>/dev/null && echo "== Screenshot: screen.png"
log show --start "$log_start" --style compact --predicate "process == \"$name\"" 2>/dev/null | tail -80 > "$out/app.log"
tail -40 "$out/app.log"
ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -3
pkill -f "$name" 2>/dev/null || true
exit $status
