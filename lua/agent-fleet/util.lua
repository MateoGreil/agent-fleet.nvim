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
