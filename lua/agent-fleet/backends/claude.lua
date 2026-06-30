local M = {}

M.has_disk = true

function M.slug(cwd)
  return cwd:gsub("[^%w]", "-")
end

function M.list(cwd, sessions_dir)
  local dir = sessions_dir .. "/" .. M.slug(cwd)
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  local entries = {}
  local names = vim.fn.readdir(dir)
  for _, name in ipairs(names) do
    if name:match("%.jsonl$") then
      local file = dir .. "/" .. name
      local id = name:gsub("%.jsonl$", "")
      local st = vim.loop.fs_stat(file)
      local created_at = 0
      if st then
        if st.birthtime and st.birthtime.sec > 0 then
          created_at = st.birthtime.sec * 1000
        elseif st.mtime then
          created_at = st.mtime.sec * 1000
        end
      end
      entries[#entries + 1] = {
        id = id,
        cwd = cwd,
        created_at = created_at,
        file = file,
      }
    end
  end

  table.sort(entries, function(a, b)
    return a.created_at < b.created_at
  end)

  return entries
end

local BLOCK_SIZE = 65536
local BUDGET = 1048576

function M.tail_info(file)
  if not file then
    return nil
  end
  local fd = io.open(file, "rb")
  if not fd then
    return nil
  end

  local st = vim.loop.fs_stat(file)
  local last_activity = st and st.mtime and st.mtime.sec * 1000 or 0

  local size = fd:seek("end")
  if size == 0 then
    fd:close()
    return { state = "unknown", last_activity = last_activity }
  end

  local blocks = {}
  local total_read = 0
  local pos = size

  while pos > 0 and total_read < BUDGET do
    local read_size = math.min(BLOCK_SIZE, pos, BUDGET - total_read)
    pos = pos - read_size
    fd:seek("set", pos)
    local chunk = fd:read(read_size)
    if not chunk then
      break
    end
    table.insert(blocks, 1, chunk)
    total_read = total_read + #chunk
  end

  fd:close()

  local content = table.concat(blocks)
  local lines = vim.split(content, "\n", { plain = true })

  local state = nil
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" then
        local msg_type = decoded.type
        if msg_type == "user" then
          if type(decoded.message) == "table" then
            state = "working"
            break
          end
        elseif msg_type == "assistant" then
          if type(decoded.message) == "table" then
            if decoded.isApiErrorMessage == true or decoded.apiErrorStatus or decoded.error then
              state = "error"
            else
              local stop_reason = decoded.message.stop_reason
              if stop_reason == "tool_use" then
                state = "working"
              else
                state = "idle"
              end
            end
            break
          end
        end
      end
    end
  end

  if not state then
    state = "unknown"
  end

  return { state = state, last_activity = last_activity }
end

function M.session_file(cwd, sessions_dir, id)
  local path = sessions_dir .. "/" .. M.slug(cwd) .. "/" .. id .. ".jsonl"
  if vim.fn.filereadable(path) == 1 then
    return path
  end
  return nil
end

return M
