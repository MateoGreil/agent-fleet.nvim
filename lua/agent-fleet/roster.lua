local M = {}

local function data_dir()
  return vim.fn.stdpath("data") .. "/agent-fleet"
end

local function roster_path()
  return data_dir() .. "/roster.json"
end

local function now_ms()
  return os.time() * 1000
end

local function empty_roster()
  return { version = 1, agents = {} }
end

function M.load()
  local path = roster_path()
  local fd = io.open(path, "r")
  if not fd then
    return empty_roster()
  end
  local raw = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or type(decoded.agents) ~= "table" then
    return empty_roster()
  end
  decoded.version = decoded.version or 1
  return decoded
end

local function save(roster)
  local dir = data_dir()
  vim.fn.mkdir(dir, "p")
  local path = roster_path()
  local tmp = path .. ".tmp"
  local fd = io.open(tmp, "w")
  fd:write(vim.json.encode(roster))
  fd:close()
  os.rename(tmp, path)
end

local function find(roster, id)
  for i, entry in ipairs(roster.agents) do
    if entry.id == id then
      return i, entry
    end
  end
  return nil, nil
end

function M.add(entry)
  if type(entry.id) ~= "string" or entry.id == "" then
    error("roster.add: entry.id must be a non-empty string")
  end
  entry.done = entry.done or false
  entry.archived = entry.archived or false
  entry.created_at = entry.created_at or now_ms()

  local roster = M.load()
  local idx = find(roster, entry.id)
  if idx then
    roster.agents[idx] = entry
  else
    roster.agents[#roster.agents + 1] = entry
  end
  save(roster)
  return entry
end

function M.ensure(entry)
  local existing = M.get(entry.id)
  if existing then
    return existing
  end
  return M.add(entry)
end

function M.get(id)
  local _, entry = find(M.load(), id)
  return entry
end

local function update(id, mutate)
  local roster = M.load()
  local _, entry = find(roster, id)
  if not entry then
    return nil
  end
  mutate(entry)
  save(roster)
  return entry
end

function M.set_name(id, name)
  return update(id, function(entry)
    entry.name = name
  end)
end

function M.mark_done(id)
  return update(id, function(entry)
    entry.done = true
  end)
end

function M.set_archived(id, archived)
  return update(id, function(entry)
    entry.archived = archived
  end)
end

function M.list(opts)
  opts = opts or {}
  local roster = M.load()
  local result = {}
  for order, entry in ipairs(roster.agents) do
    local keep = true
    if opts.cwd and entry.cwd ~= opts.cwd then
      keep = false
    end
    if not opts.include_archived and entry.archived == true then
      keep = false
    end
    if keep then
      result[#result + 1] = { entry = entry, order = order }
    end
  end
  table.sort(result, function(a, b)
    if a.entry.created_at == b.entry.created_at then
      return a.order < b.order
    end
    return a.entry.created_at < b.entry.created_at
  end)
  local entries = {}
  for i, item in ipairs(result) do
    entries[i] = item.entry
  end
  return entries
end

return M
