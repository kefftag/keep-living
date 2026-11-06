#!/bin/bash
# Builds release exports for every preset in export_presets.cfg into build/,
# then runs the headless smoke test inside the macOS build as a sanity check.
#
#   tools/release/build.sh            # all platforms
#   tools/release/build.sh macOS      # one preset
#
# Needs the Godot export templates matching the editor version
# (Editor > Manage Export Templates, or the .tpz from the Godot release page).
set -euo pipefail
cd "$(dirname "$0")/../.."
G="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PRESETS=("${@:-macOS Windows Linux}")
read -ra PRESETS <<< "${PRESETS[*]}"
"$G" --headless --path . --import >/dev/null 2>&1 || true
for p in "${PRESETS[@]}"; do
  case "$p" in
    macOS) mkdir -p build/macos ;; Windows) mkdir -p build/windows ;; Linux) mkdir -p build/linux ;;
  esac
  echo "== $p"
  "$G" --headless --path . --export-release "$p" 2>&1 | grep -E "ERROR" -A2 || true
done
if [[ " ${PRESETS[*]} " == *" macOS "* ]] && [ -f build/macos/KeepLiving.zip ]; then
  rm -rf build/macos/app && mkdir -p build/macos/app && unzip -q build/macos/KeepLiving.zip -d build/macos/app
  echo "== smoke test in the exported macOS app"
  build/macos/app/*.app/Contents/MacOS/* --headless -- --smoke-test 2>&1 | grep -E "SMOKE|FAIL"
fi
ls -la build/*/ 2>/dev/null
