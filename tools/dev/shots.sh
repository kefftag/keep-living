#!/bin/bash
# Screenshot run of the smoke test that doesn't disturb whoever is using the Mac:
# Godot is launched in the background (never brought to the front), the window
# can't take focus or catch clicks, and the mouse is never captured.
#
#   tools/dev/shots.sh /abs/path/to/shots [project dir]
#
# Prints the smoke-test result lines; exits 0 only on SMOKE OK.
set -u
OUT="${1:?usage: tools/dev/shots.sh /abs/shots/dir [project dir]}"
PROJ="${2:-$(cd "$(dirname "$0")/../.." && pwd)}"
APP="${GODOT_APP:-/Applications/Godot.app}"
mkdir -p "$OUT"
LOG="$OUT/godot.log"
rm -f "$LOG"
# -g: don't bring to front, -W: wait until it quits, -n: separate instance.
open -g -W -n -a "$APP" --args --path "$PROJ" --audio-driver Dummy --log-file "$LOG" -- --smoke-test --shots="$OUT"
grep -E "^\s*(ok|FAIL|shot)|SMOKE" "$LOG"
grep -q "SMOKE OK" "$LOG"
