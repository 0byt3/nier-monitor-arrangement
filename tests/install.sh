#!/usr/bin/env bash
# Stage the standalone installation; never write system files or user config.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
export HOME=$stage/home
mkdir -p "$HOME/.config/hypr"
printf '%s\n' '-- keep this user config' > "$HOME/.config/hypr/monitors.lua"
cp "$HOME/.config/hypr/monitors.lua" "$stage/before"
bash "$root/install.sh" --skip-build --destdir "$stage/system" > /dev/null
cmp "$HOME/.config/hypr/monitors.lua" "$stage/before"
cmp "$root/hypr/runtime.lua" "$stage/system/usr/local/nier/share/hypr/monitor-arrangement-runtime.lua"
[[ ! -e $stage/system/usr/share/nier/plugins/nier.monitor-arrangement/runtime.lua ]]
for file in nier-monitor-arrangement nier-monitor-arrangement-backend nier-monitor-arrangement-enable; do
  test -x "$stage/system/usr/share/nier/bin/$file"
done
[[ $(readlink "$stage/system/usr/bin/nier-monitor-arrangement") == /usr/share/nier/bin/nier-monitor-arrangement ]]
cmp "$root/qml/Editor.qml" "$stage/system/usr/share/nier/plugins/nier.monitor-arrangement/Editor.qml"
cmp "$root/packaging/nier-monitor-arrangement.svg" "$stage/system/usr/share/nier/plugins/nier.monitor-arrangement/nier-monitor-arrangement.svg"
test -f "$stage/system/usr/share/applications/nier-monitor-arrangement.desktop"
# Reinstalling the same files is safe and still does not edit HOME.
bash "$root/install.sh" --skip-build --destdir "$stage/system" > /dev/null
cmp "$HOME/.config/hypr/monitors.lua" "$stage/before"
if bash "$root/install.sh" --skip-build --destdir relative >/dev/null 2>&1; then exit 1; fi
if bash "$root/install.sh" --unknown >/dev/null 2>&1; then exit 1; fi
printf '%s\n' 'PASS: staged standalone install, canonical runtime, launchers/assets/icon, repeat install and untouched HOME'
