local M = {}

M.has_disk = true

function M.cwd_slug(cwd)
  return "--" .. cwd:gsub("/", "-"):gsub("^%-+", ""):gsub("%-+$", "") .. "--"
end

M.slug = M.cwd_slug

local function read_first_line(file)
  local fd = io.open(file, "r")
  if not fd then
    return nil
  end
  local line = fd:read("*l")
  fd:close()
  return line
end

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
  local ms = ts:match("%.(%d+)") or "0"
  ms = tonumber((ms .. "000"):sub(1, 3)) or 0
  return epoch * 1000 + ms
end

local function id_from_filename(name)
  return name:match(".*_(.+)%.jsonl$")
end

local function mtime_ms(file)
  local st = vim.loop.fs_stat(file)
  if st and st.mtime then
    return st.mtime.sec * 1000
  end
  return 0
end

function M.list(cwd, sessions_dir)
  local dir = sessions_dir .. "/" .. M.cwd_slug(cwd)
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  local entries = {}
  local names = vim.fn.readdir(dir)
  for _, name in ipairs(names) do
    if name:match("%.jsonl$") then
      local file = dir .. "/" .. name
      local header = {}
      local line = read_first_line(file)
      if line then
        local ok, decoded = pcall(vim.json.decode, line)
        if ok and type(decoded) == "table" then
          header = decoded
        end
      end

      local id = header.id or id_from_filename(name)
      if id then
        local created_at = parse_iso_ms(header.timestamp) or mtime_ms(file)
        entries[#entries + 1] = {
          id = id,
          cwd = header.cwd,
          created_at = created_at,
          file = file,
        }
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.created_at < b.created_at
  end)

  return entries
end

local CHUNK = 16384

local function message_state(decoded)
  local message = decoded.message
  if type(message) ~= "table" then
    return "working"
  end
  if message.role == "assistant" then
    local reason = message.stopReason
    if reason == "toolUse" then
      return "working"
    elseif reason == "aborted" then
      return "stopped"
    elseif reason == "error" then
      return "error"
    end
    return "idle"
  end
  return "working"
end

function M.tail_info(file)
  if not file then
    return nil
  end
  local fd = io.open(file, "rb")
  if not fd then
    return nil
  end
  local size = fd:seek("end")
  local start = math.max(0, size - CHUNK)
  local from_start = (start == 0)
  fd:seek("set", start)
  local chunk = fd:read("*a") or ""
  fd:close()

  local lines = vim.split(chunk, "\n", { plain = true })
  if start > 0 and #lines > 0 then
    table.remove(lines, 1)
  end

  local last_activity = nil
  local state = nil
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" then
        if not last_activity and type(decoded.timestamp) == "string" then
          last_activity = parse_iso_ms(decoded.timestamp)
        end
        if not state and decoded.type == "message" then
          state = message_state(decoded)
        end
      end
    end
    if last_activity and state then
      break
    end
  end

  return {
    state = state or (from_start and "new" or "unknown"),
    last_activity = last_activity or mtime_ms(file),
  }
end

function M.session_file(cwd, sessions_dir, id)
  local pattern = sessions_dir .. "/**/*_" .. id .. ".jsonl"
  local matches = vim.fn.glob(pattern, true, true)
  if type(matches) == "table" and #matches > 0 then
    return matches[1]
  end
  return nil
end

return M
