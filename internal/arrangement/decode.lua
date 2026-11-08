-- Decode a returned data table, with no globals available to the document.
local source = io.read("*a")
local chunk, err = load(source, "monitor-arrangement.lua", "t", {})
if not chunk then error(err) end
local budget = 0
debug.sethook(function()
  budget = budget + 10000
  if budget > 1000000 then error("arrangement data exceeded the instruction budget") end
end, "", 10000)
local ok, data = pcall(chunk)
debug.sethook()
if not ok then error(data) end
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return string.format("\\u%04x", string.byte(c))
  end) .. '"'
end
local seen = {}
local function encode(value, depth)
  if type(value) == "boolean" then return tostring(value) end
  if type(value) == "number" then
    if value ~= value or value == math.huge or value == -math.huge then error("invalid number") end
    return tostring(value)
  end
  if type(value) ~= "table" or depth > 3 or seen[value] then error("expected a plain arrangement table") end
  seen[value] = true
  local result, count = {}, 0
  for key, child in pairs(value) do
    count = count + 1
    if count > 256 or type(key) ~= "string" or #key > 65536 then error("invalid arrangement key") end
    result[#result + 1] = quote(key) .. ":" .. encode(child, depth + 1)
  end
  seen[value] = nil
  return "{" .. table.concat(result, ",") .. "}"
end
io.write(encode(data, 0))
