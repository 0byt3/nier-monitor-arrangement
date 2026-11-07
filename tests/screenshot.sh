#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-$root/docs/preview.png}
stage=$(mktemp -d)
pid=''
trap 'if [[ -n $pid ]]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi; rm -rf -- "$stage"' EXIT
mkdir -p "$stage/runtime" "$stage/home" "$(dirname "$output")"
chmod 700 "$stage/runtime"
export HOME=$stage/home XDG_RUNTIME_DIR=$stage/runtime QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software
quickshell -p "$root/qml/preview.qml" --no-color > "$stage/log" 2>&1 &
pid=$!
for ((attempt=0;attempt<50;attempt++)); do
  if quickshell ipc -p "$root/qml/preview.qml" call arrangement status 2>/dev/null | jq -e .ready >/dev/null 2>/dev/null; then break; fi
  sleep 0.1
done
sleep 0.2
quickshell ipc -p "$root/qml/preview.qml" call arrangement capture "$output"
for ((attempt=0;attempt<30;attempt++)); do [[ -s $output ]] && break; sleep 0.1; done
[[ -s $output ]] || { cat "$stage/log"; exit 1; }
printf 'Saved preview: %s\n' "$output"
