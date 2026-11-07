#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
export HOME=$stage/home
mkdir -p "$HOME/.config/hypr" "$stage/bin"
cat > "$stage/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ $1 == configerrors && ${NIER_TEST_CONFIG_ERROR:-} == true ]]; then echo 'fixture config error'; else exit 0; fi
SH
chmod +x "$stage/bin/hyprctl"
export PATH=$stage/bin:$PATH
cat > "$HOME/.config/hypr/monitors.lua" <<'LUA'
-- External monitors run left to right in discovery order; laptop goes last.
local obsolete = true
-- Monitor scale is Hyprland's scale for the output.
hl.monitor({ output = "DP-1", scale = 1.25 })
-- Run after the monitor rules above have been applied.
schedule_layout()
LUA
bash "$root/bin/enable-hyprland" > /dev/null
luac -p "$HOME/.config/hypr/monitors.lua"
grep -q 'scale = 1.25' "$HOME/.config/hypr/monitors.lua"
! grep -q 'obsolete\|schedule_layout' "$HOME/.config/hypr/monitors.lua"
cp "$HOME/.config/hypr/monitors.lua" "$stage/first"
bash "$root/bin/enable-hyprland" >/dev/null
cmp "$stage/first" "$HOME/.config/hypr/monitors.lua"
[[ $(find "$HOME" -name '*.before-arrangement.*' | wc -l) == 1 ]]
printf 'hl.monitor({ output = "DP-1", scale = 2 })\n' > "$HOME/.config/hypr/monitors.lua"
cp "$HOME/.config/hypr/monitors.lua" "$stage/original"
if NIER_TEST_CONFIG_ERROR=true bash "$root/bin/enable-hyprland" >/dev/null 2>&1; then exit 1; fi
cmp "$stage/original" "$HOME/.config/hypr/monitors.lua"
printf '%s\n' 'PASS: managed loader, old-helper replacement, preserved rules, idempotence and rollback'
