local M = {}

function M.cwd_slug(cwd)
  return "--" .. cwd:gsub("/", "-"):gsub("^%-+", ""):gsub("%-+$", "") .. "--"
end

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

return M
