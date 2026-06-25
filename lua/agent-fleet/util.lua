local M = {}

local seeded = false

local function fallback_uuid()
  if not seeded then
    math.randomseed(os.time() + os.clock() * 1000000)
    seeded = true
  end
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

function M.relative_time(ms, now_ms)
  local diff = math.max(0, now_ms - ms)
  local s = diff / 1000
  if s < 60 then
    return "now"
  elseif s < 3600 then
    return string.format("%dm", math.floor(s / 60))
  elseif s < 86400 then
    return string.format("%dh", math.floor(s / 3600))
  elseif s < 604800 then
    return string.format("%dd", math.floor(s / 86400))
  end
  return string.format("%dw", math.floor(s / 604800))
end

function M.uuid()
  if vim.fn.executable("uuidgen") == 1 then
    local raw = vim.fn.system("uuidgen")
    local id = vim.trim(raw):lower()
    if id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
      return id
    end
  end
  return fallback_uuid()
end

return M
