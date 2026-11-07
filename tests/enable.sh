#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
export HOME=$stage/home
export NIER_PATH=$stage/nier
export NIER_MONITOR_ARRANGEMENT_BACKEND=$root/build/nier-monitor-arrangement-backend
mkdir -p "$NIER_PATH/share/hypr"
printf 'runtime_loaded = true\n' > "$NIER_PATH/share/hypr/monitor-arrangement-runtime.lua"
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
grep -Fq 'os.getenv("NIER_PATH")' "$HOME/.config/hypr/monitors.lua"
! grep -Fq "$root" "$HOME/.config/hypr/monitors.lua"
! grep -Fq "$stage" "$HOME/.config/hypr/monitors.lua"
lua -E - "$HOME/.config/hypr/monitors.lua" <<'LUA'
hl = { monitor = function() end }
dofile(arg[1])
assert(runtime_loaded, "the hook did not resolve NIER_PATH")
-- The installer shell can have a different value from the compositor.
local original_dofile = dofile
local original_getenv = os.getenv
for _, case in ipairs({
  { false, "/usr/local/nier" },
  { "", "/usr/local/nier" },
  { "/usr/local/nier", "/usr/local/nier" },
  { "/usr/local/nier///", "/usr/local/nier" },
  { original_getenv("NIER_PATH") .. "///", original_getenv("NIER_PATH") },
}) do
  local resolved
  os.getenv = function(name)
    if name == "NIER_PATH" then return case[1] or nil end
    return original_getenv(name)
  end
  dofile = function(path) resolved = path end
  original_dofile(arg[1])
  assert(resolved == case[2] .. "/share/hypr/monitor-arrangement-runtime.lua", "incorrect compositor path: " .. tostring(resolved))
end
os.getenv = original_getenv
dofile = original_dofile
LUA
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
# Preflight resolves a trailing slash just like the compositor loader.
NIER_PATH="$NIER_PATH///" bash "$root/bin/enable-hyprland" >/dev/null
# Offline enable must not contact a compositor.
cat > "$stage/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
echo contacted-compositor >> "$HOME/contacted"
exit 1
SH
bash "$root/bin/enable-hyprland" --no-reload >/dev/null
[[ ! -e $HOME/contacted ]]
grep -Fq 'os.getenv("NIER_PATH")' "$HOME/.config/hypr/monitors.lua"
printf '%s\n' 'PASS: NIER_PATH loader, no checkout paths, preserved rules, idempotence, rollback and offline enable'
