local M = {}

M.has_disk = true

M._snapshots = {}

M._inflight = {}

local REFRESH_TIMEOUT_MS = 10000

local BIND_TOLERANCE_MS = 5000

local function mono_ms()
  return math.floor(vim.loop.hrtime() / 1e6)
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
      entry.agent == "opencode"
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
        type = "opencode",
        name = entry.name,
        cwd = entry.cwd,
        auto_named = entry.auto_named or false,
      })
      next_agent = next_agent + 1
    end
  end
end

local function decode_column(value)
  if value == nil or value == vim.NIL then
    return nil, "null"
  end
  if type(value) ~= "string" then
    return nil, "corrupt"
  end
  local ok, decoded = pcall(vim.json.decode, value)
  if not ok or type(decoded) ~= "table" then
    return nil, "corrupt"
  end
  return decoded, "ok"
end

function M.sql_quote(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

function M.build_query(cwd)
  return table.concat({
    "SELECT s.id, s.title, s.directory, s.time_created, s.time_updated,",
    "(SELECT m.data FROM message m WHERE m.session_id = s.id ORDER BY m.time_created DESC, m.id DESC LIMIT 1) AS last_message,",
    "(SELECT p.data FROM part p WHERE p.session_id = s.id ORDER BY p.time_created DESC, p.id DESC LIMIT 1) AS last_part",
    "FROM session s",
    "WHERE s.directory = " .. M.sql_quote(cwd),
    "ORDER BY s.time_created ASC",
  }, " ")
end

function M._derive_state(message, part, part_corrupt)
  if type(message) ~= "table" then
    return "new"
  end
  if message.role ~= "assistant" then
    return "working"
  end
  if part_corrupt then
    return "unknown"
  end
  if type(part) == "table" then
    if part.type == "retry" then
      return "error"
    end
    if part.type == "step-start" then
      return "working"
    end
    if part.type == "tool" and type(part.state) == "table" then
      local status = part.state.status
      if status == "error" then
        return "error"
      end
      if status == "pending" or status == "running" then
        return "working"
      end
    end
  end
  return "idle"
end

function M.parse_snapshot(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or (next(decoded) ~= nil and decoded[1] == nil) then
    return nil
  end
  local rows = {}
  for _, item in ipairs(decoded) do
    if type(item) == "table" and type(item.id) == "string" then
      local message, message_status = decode_column(item.last_message)
      local part, part_status = decode_column(item.last_part)
      local state
      if message_status == "null" then
        state = "new"
      elseif message_status == "corrupt" then
        state = "unknown"
      else
        state = M._derive_state(message, part, part_status == "corrupt")
      end
      rows[#rows + 1] = {
        id = item.id,
        cwd = item.directory,
        created_at = tonumber(item.time_created) or 0,
        last_activity = tonumber(item.time_updated) or 0,
        title = type(item.title) == "string" and item.title or nil,
        state = state,
      }
    end
  end
  return rows
end

function M.list(cwd, _)
  local snap = M._snapshots[cwd]
  if not snap then
    return {}
  end
  return snap.rows
end

function M.tail_info()
  return nil
end

function M.db_path(def)
  local dir = def and def.sessions_dir
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  return dir .. "/opencode.db"
end

function M._apply_snapshot(cwd, raw)
  local rows = M.parse_snapshot(raw)
  if rows == nil then
    return false
  end
  M._snapshots[cwd] = { rows = rows, fetched_mono = mono_ms() }
  M._bind_sessions(cwd, rows)
  return true
end

function M.session_file(cwd, def, id)
  local db = M.db_path(def)
  if not db or vim.fn.filereadable(db) ~= 1 then
    return nil
  end
  local snap = M._snapshots[cwd]
  if not snap then
    return db
  end
  for _, row in ipairs(snap.rows) do
    if row.id == id then
      return db
    end
  end
  return nil
end

function M.refresh(cwd, def)
  local cmd = def and def.cmd
  if type(cmd) ~= "string" or cmd == "" then
    return
  end
  if vim.fn.isdirectory(cwd) ~= 1 then
    return
  end
  if M._inflight[cwd] then
    return
  end
  local snap = M._snapshots[cwd]
  local interval = require("agent-fleet.config").get().board.refresh_ms
  if snap and mono_ms() - snap.fetched_mono < interval then
    return
  end

  M._inflight[cwd] = true
  local out = {}
  local timer
  local job = vim.fn.jobstart({ cmd, "db", M.build_query(cwd), "--format", "json" }, {
    cwd = cwd,
    stdin = "null",
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        out[#out + 1] = line
      end
    end,
    on_exit = function(_, code)
      if timer then
        pcall(vim.fn.timer_stop, timer)
      end
      M._inflight[cwd] = nil
      if code == 0 then
        M._apply_snapshot(cwd, table.concat(out, "\n"))
      end
    end,
  })
  if job <= 0 then
    M._inflight[cwd] = nil
    return
  end
  timer = vim.fn.timer_start(REFRESH_TIMEOUT_MS, function()
    pcall(vim.fn.jobstop, job)
    M._inflight[cwd] = nil
  end)
end

return M
