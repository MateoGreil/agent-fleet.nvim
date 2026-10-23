local M = {}

M.has_disk = true

local BIND_TOLERANCE_MS = 5000

local function parse_iso_ms(ts)
  if type(ts) ~= "string" then
    return nil
  end
  local y, mo, d, h, mi, s = ts:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return nil
  end
  local epoch = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
    isdst = false,
  })
  local offset = os.difftime(os.time(os.date("!*t", epoch)), epoch)
  epoch = epoch - offset
  local sign, oh, om = ts:match("([+-])(%d+):(%d+)$")
  if sign then
    local secs = tonumber(oh) * 3600 + tonumber(om) * 60
    if sign == "+" then
      epoch = epoch - secs
    else
      epoch = epoch + secs
    end
  end
  local ms = ts:match("%.(%d+)") or "0"
  ms = tonumber((ms .. "000"):sub(1, 3)) or 0
  return epoch * 1000 + ms
end

local function is_null(v)
  return v == nil or v == vim.NIL
end

local function session_state(meta)
  if is_null(meta.end_time) then
    return "working"
  end
  return "idle"
end

local function read_meta(file)
  local fd = io.open(file, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

function M._bind_sessions(cwd, rows)
  local agent_mod = require("agent-fleet.agent")
  local roster = require("agent-fleet.roster")

  local bound_ids = {}
  local unbound = {}
  for _, entry in pairs(agent_mod.agents) do
    if type(entry.session_id) == "string" then
      bound_ids[entry.session_id] = true
    elseif
      entry.agent == "vibe"
      and entry.cwd == cwd
      and type(entry.spawned_ms) == "number"
    then
      unbound[#unbound + 1] = entry
    end
  end
  if #unbound == 0 then
    return
  end
  table.sort(unbound, function(x, y)
    return x.spawned_ms < y.spawned_ms
  end)

  local claimed = {}
  for _, entry in ipairs(roster.list({ cwd = cwd, include_archived = true })) do
    claimed[entry.id] = true
  end

  local candidates = {}
  for _, row in ipairs(rows) do
    if not bound_ids[row.id] and not claimed[row.id] then
      candidates[#candidates + 1] = row
    end
  end
  table.sort(candidates, function(x, y)
    return x.created_at < y.created_at
  end)

  local next_agent = 1
  for _, row in ipairs(candidates) do
    local entry = unbound[next_agent]
    if not entry then
      break
    end
    if row.created_at >= entry.spawned_ms - BIND_TOLERANCE_MS then
      entry.session_id = row.id
      roster.add({
        id = row.id,
        type = "vibe",
        name = entry.name,
        cwd = entry.cwd,
        auto_named = entry.auto_named or false,
      })
      next_agent = next_agent + 1
    end
  end
end

function M.list(cwd, def)
  local dir = def.sessions_dir .. "/unified"
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  local entries = {}
  local names = vim.fn.readdir(dir)
  for _, name in ipairs(names) do
    local file = dir .. "/" .. name .. "/meta.json"
    if vim.fn.filereadable(file) == 1 then
      local meta = read_meta(file)
      if
        meta
        and type(meta.session_id) == "string"
        and is_null(meta.parent_session_id)
        and meta.origin_directory == cwd
      then
        entries[#entries + 1] = {
          id = meta.session_id,
          cwd = meta.origin_directory,
          created_at = parse_iso_ms(meta.start_time) or 0,
          last_activity = parse_iso_ms(meta.bumped_at) or 0,
          title = type(meta.title) == "string" and meta.title or ("vibe:" .. meta.session_id:sub(1, 8)),
          state = session_state(meta),
          file = file,
          archived = (not is_null(meta.archived_at) and meta.archived_at ~= false) or nil,
        }
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.created_at < b.created_at
  end)

  M._bind_sessions(cwd, entries)

  return entries
end

function M.tail_info(file)
  if not file then
    return nil
  end
  local meta = read_meta(file)
  if not meta then
    return nil
  end
  return {
    state = session_state(meta),
    last_activity = parse_iso_ms(meta.bumped_at) or 0,
  }
end

function M.session_file(cwd, def, id)
  local path = def.sessions_dir .. "/unified/" .. id .. "/meta.json"
  if vim.fn.filereadable(path) == 1 then
    return path
  end
  return nil
end

return M
