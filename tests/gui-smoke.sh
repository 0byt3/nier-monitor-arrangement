#!/usr/bin/env bash
# Real QML process/GUI/save flow against fictional monitors and temporary HOME.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
shell_pid=''
cleanup() {
  if [[ -n $shell_pid ]]; then kill "$shell_pid" 2>/dev/null || :; wait "$shell_pid" 2>/dev/null || :; fi
  rm -rf -- "$stage"
}
trap cleanup EXIT
export HOME=$stage/home XDG_RUNTIME_DIR=$stage/runtime
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software
export NIER_MONITOR_ARRANGEMENT_BACKEND=$root/build/nier-monitor-arrangement-backend
export NIER_TEST_MONITORS=$stage/monitors.json NIER_TEST_NEXT=$stage/next.json NIER_TEST_EVAL=$stage/eval.lua
mkdir -p "$HOME/.config/omarchy" "$XDG_RUNTIME_DIR" "$stage/bin"
chmod 700 "$XDG_RUNTIME_DIR"
cat > "$NIER_TEST_MONITORS" <<'JSON'
[{"name":"DP-1","description":"Studio <display>","model":"Studio","serial":"EXTERNAL-01","width":2560,"height":1440,"scale":1,"transform":0,"x":0,"y":0},{"name":"eDP-1","description":"Laptop","model":"Laptop","serial":"LAPTOP-01","width":1920,"height":1200,"scale":1.25,"transform":0,"x":2560,"y":0}]
JSON
jq '.[0].y = -200' "$NIER_TEST_MONITORS" > "$NIER_TEST_NEXT"
cat > "$stage/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == monitors ]]; then cat "$NIER_TEST_MONITORS"
elif [[ $1 == eval ]]; then printf '%s' "$2" > "$NIER_TEST_EVAL"; cp "$NIER_TEST_NEXT" "$NIER_TEST_MONITORS"; printf 'ok\n'
else exit 1; fi
SH
chmod +x "$stage/bin/hyprctl"
export PATH=$stage/bin:$PATH
quickshell -p "$root/qml/shell.qml" --no-color > "$stage/gui.log" 2>&1 &
shell_pid=$!
ipc() { quickshell ipc -p "$root/qml/shell.qml" call arrangement "$@"; }
for ((attempt=0;attempt<80;attempt++)); do
  if ipc status > "$stage/status.json" 2>/dev/null && jq -e '.ready and (.busy|not)' "$stage/status.json" >/dev/null; then break; fi
  sleep 0.1
done
jq -e '.ready' "$stage/status.json" >/dev/null || { cat "$stage/gui.log"; exit 1; }
ipc move DP-1 0 -200
ipc primary DP-1
ipc status | jq -e '.primary == "DP-1"' >/dev/null
ipc status | jq -e '.dirty and (.overlapping|not)' >/dev/null
# A second launch must reopen the same editor and preserve unsaved changes.
timeout 5 bash "$root/bin/nier-monitor-arrangement" open
ipc status | jq -e '.dirty and .primary == "DP-1" and .monitors[0].y == -200' >/dev/null
ipc save
for ((attempt=0;attempt<80;attempt++)); do
  ipc status > "$stage/status.json"
  if jq -e '(.busy|not) and (.dirty|not) and .message == "Saved and applied."' "$stage/status.json" >/dev/null; then break; fi
  sleep 0.1
done
jq -e '.message == "Saved and applied."' "$stage/status.json" >/dev/null || { cat "$stage/status.json" "$stage/gui.log"; exit 1; }
"$NIER_MONITOR_ARRANGEMENT_BACKEND" snapshot | jq -e '.snapshot.arrangement["EXTERNAL-01"].y == -200 and .snapshot.arrangement["EXTERNAL-01"].primary == true and .snapshot.primary == "DP-1"' >/dev/null
lua -E - "$NIER_TEST_EVAL" <<'LUA'
hl = {monitor=function() end}
dofile(arg[1])
assert(NIER_PRIMARY_MONITOR == "DP-1")
LUA
# Language switches are confined to the test HOME, not the user's preferences.
printf 'da\n' > "$HOME/.config/omarchy/language"
sleep 0.3
ipc status | jq -e '.message == "Gemt og anvendt."' >/dev/null
if rg 'ERROR|TypeError|ReferenceError|Binding loop|Unable to assign' "$stage/gui.log"; then exit 1; fi
ipc capture "$stage/editor.png"
sleep 0.3
[[ -s $stage/editor.png ]]
if [[ -n ${NIER_GUI_CAPTURE:-} ]]; then cp "$stage/editor.png" "$NIER_GUI_CAPTURE"; fi
printf '%s\n' 'PASS: QML discovery, primary selection/global, vertical edit, save/apply, persisted Lua, language reload and screenshot'
