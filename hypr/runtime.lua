-- Load after the user's monitor mode/scale rules. The backend owns identity
-- matching so it uses the same serial/model/tie-break rules as the editor.
local helper = ... or os.getenv("NIER_MONITOR_ARRANGEMENT_BACKEND")
  or "/usr/share/nier/bin/nier-monitor-arrangement-backend"
local pending = false
local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end
local function apply_arrangement()
  if pending then return end
  pending = true
  hl.timer(function()
    pending = false
    hl.exec_cmd(shell_quote(helper) .. " apply")
  end, { type = "oneshot", timeout = 200 })
end
hl.on("monitor.added", apply_arrangement)
hl.on("monitor.removed", apply_arrangement)
hl.on("hyprland.start", apply_arrangement)
hl.on("config.reloaded", apply_arrangement)
apply_arrangement()
