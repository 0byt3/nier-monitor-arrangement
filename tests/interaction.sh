#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/runtime" "$stage/home"
chmod 700 "$stage/runtime"
status=0
HOME="$stage/home" XDG_RUNTIME_DIR="$stage/runtime" QT_QPA_PLATFORM=offscreen \
 QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software \
 timeout 12 quickshell -p "$root/qml/interaction.qml" --no-color > "$stage/log" 2>&1 || status=$?
cat "$stage/log"
(( status == 0 ))
grep -q 'PASS: real pointer drag' "$stage/log"
if rg 'FAIL:|ERROR|TypeError|ReferenceError|Binding loop|Unable to assign' "$stage/log"; then exit 1; fi
