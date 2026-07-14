local M = {}

local function live_by_cwd(cwd)
  local agent = require("agent-fleet.agent")
  local result = {}
  for _, entry in pairs(agent.agents) do
    if entry.session_id ~= nil and entry.cwd == cwd then
      result[entry.session_id] = entry
    end
  end
  return result
end

local function index_by_id(items)
  local result = {}
  for _, item in ipairs(items) do
    result[item.id] = item
  end
  return result
end

function M.rows(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local cfg = require("agent-fleet.config").get()
  local include_archived = opts.include_archived or false

  local live = live_by_cwd(cwd)
  local backends = require("agent-fleet.backends")
  local disk = {}
  local disk_types = {}
  for agent_type, def in pairs(cfg.agents) do
    local backend = backends.resolve(agent_type)
    if backend.has_disk then
      local sdir = opts.sessions_dir or def.sessions_dir
      for _, entry in ipairs(backend.list(cwd, sdir)) do
        disk[entry.id] = entry
        disk_types[entry.id] = agent_type
      end
    end
  end
  local roster = index_by_id(
    require("agent-fleet.roster").list({ cwd = cwd, include_archived = true })
  )

  local ids = {}
  local seen = {}
  local function collect(id)
    if id ~= nil and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for id in pairs(live) do
    collect(id)
  end
  for id in pairs(disk) do
    collect(id)
  end
  for id in pairs(roster) do
    collect(id)
  end

  local rows = {}
  for _, id in ipairs(ids) do
    local live_entry = live[id]
    local disk_entry = disk[id]
    local roster_entry = roster[id]

    local is_live = false
    local bufnr = nil
    if live_entry and live_entry.bufnr and vim.api.nvim_buf_is_valid(live_entry.bufnr) then
      is_live = true
      bufnr = live_entry.bufnr
    end

    local row_type
    if live_entry then
      row_type = live_entry.agent
    elseif roster_entry then
      row_type = roster_entry.type
    elseif disk_entry then
      row_type = disk_types[id]
    end

    local name
    if roster_entry then
      name = roster_entry.name
    elseif live_entry then
      name = live_entry.name
    else
      name = (row_type or "pi") .. ":" .. id:sub(1, 8)
    end

    local done = roster_entry and roster_entry.done or false
    local archived = roster_entry and roster_entry.archived or false

    local created_at = 0
    if disk_entry then
      created_at = disk_entry.created_at
    elseif roster_entry then
      created_at = roster_entry.created_at or 0
    end

    if include_archived or not archived then
      local file = disk_entry and disk_entry.file or nil
      local state = "new"
      local last_activity = created_at
      if file and row_type then
        local backend = backends.resolve(row_type)
        local info = backend.tail_info(file)
        if info then
          state = info.state
          last_activity = info.last_activity
        end
      end
      rows[#rows + 1] = {
        id = id,
        name = name,
        cwd = cwd,
        type = row_type,
        live = is_live,
        bufnr = bufnr,
        done = done,
        archived = archived,
        file = file,
        created_at = created_at,
        state = state,
        last_activity = last_activity,
      }
    end
  end

  table.sort(rows, function(a, b)
    if a.archived ~= b.archived then
      return not a.archived
    end
    if a.done ~= b.done then
      return not a.done
    end
    if a.live ~= b.live then
      return a.live
    end
    return a.last_activity > b.last_activity
  end)

  return rows
end

function M.format_row(row, now_ms)
  now_ms = now_ms or (os.time() * 1000)
  local prefix = row.archived and "[archived] " or ""
  local marker = row.live and "\u{25cf}" or "\u{25cb}"
  local state = row.state or "new"
  local state_col = state .. string.rep(" ", math.max(0, 8 - #state))
  local name = row.name
  if vim.fn.strchars(name) > 22 then
    name = vim.fn.strcharpart(name, 0, 21) .. "\u{2026}"
  end
  local time = (row.last_activity and row.last_activity > 0)
      and require("agent-fleet.util").relative_time(row.last_activity, now_ms)
    or "\u{2014}"
  local suffix = row.done and "  \u{2713}" or ""
  return prefix
    .. string.format("%s  %s  %s  \u{00b7}  %s", marker, state_col, name, time)
    .. suffix
end

local SECTION_ORDER = { "RUNNING", "IDLE", "DONE", "ARCHIVED" }
local SECTION_GLYPH = {
  RUNNING = "\u{25cf}",
  IDLE = "\u{25cb}",
  DONE = "\u{2713}",
  ARCHIVED = "\u{25aa}",
}
local STATE_HL = {
  working = "AgentFleetWorking",
  idle = "AgentFleetIdle",
  stopped = "AgentFleetStopped",
  error = "AgentFleetError",
  new = "AgentFleetNew",
  unknown = "AgentFleetUnknown",
}

local function section_of(row)
  if row.archived then
    return "ARCHIVED"
  elseif row.done then
    return "DONE"
  elseif row.live then
    return "RUNNING"
  end
  return "IDLE"
end

local function pad_to(s, width)
  local len = vim.fn.strchars(s)
  if len < width then
    return s .. string.rep(" ", width - len)
  end
  return s
end

local function truncate_name(name)
  if vim.fn.strchars(name) > 28 then
    return vim.fn.strcharpart(name, 0, 27) .. "\u{2026}"
  end
  return name
end

local function render_empty(opts, archived_in_rows)
  local cwd = opts.cwd or ""
  local archived_count = opts.archived_count or archived_in_rows or 0
  local placeholder = "No agents in this directory."
  if not opts.show_archived and archived_count > 0 then
    placeholder = placeholder .. "  (" .. archived_count .. " archived \u{2014} press A to show)"
  end
  local lines = {
    "agent-fleet \u{00b7} " .. cwd,
    "",
    placeholder,
    "",
    "press  a  to launch   \u{00b7}   i  to launch with a prompt",
  }
  local highlights = {
    { line = 0, col_start = 0, col_end = -1, hl_group = "AgentFleetHeader" },
  }
  return { lines = lines, highlights = highlights, line_to_row = {} }
end

function M.render(rows, opts)
  opts = opts or {}
  local now_ms = opts.now_ms or (os.time() * 1000)
  local show_archived = opts.show_archived or false

  local buckets = { RUNNING = {}, IDLE = {}, DONE = {}, ARCHIVED = {} }
  for _, row in ipairs(rows) do
    local section = section_of(row)
    buckets[section][#buckets[section] + 1] = row
  end
  local archived_in_rows = #buckets.ARCHIVED

  local visible_count = #buckets.RUNNING + #buckets.IDLE + #buckets.DONE
  if show_archived then
    visible_count = visible_count + archived_in_rows
  end
  if visible_count == 0 then
    return render_empty(opts, archived_in_rows)
  end

  local lines = {}
  local highlights = {}
  local line_to_row = {}

  for _, section in ipairs(SECTION_ORDER) do
    local section_rows = buckets[section]
    if #section_rows > 0 and (section ~= "ARCHIVED" or show_archived) then
      lines[#lines + 1] = SECTION_GLYPH[section] .. " " .. section .. "  " .. #section_rows
      highlights[#highlights + 1] =
        { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AgentFleetHeader" }

      for _, row in ipairs(section_rows) do
        local marker = row.live and "\u{25cf}" or "\u{25cb}"
        local state = row.state or "new"
        local state_col = pad_to(state, 8)
        local name_col = pad_to(truncate_name(row.name), 28)
        local time = (type(row.last_activity) == "number" and row.last_activity > 0)
            and require("agent-fleet.util").relative_time(row.last_activity, now_ms)
          or "\u{2014}"
        lines[#lines + 1] = "  " .. marker .. " " .. state_col .. "  " .. name_col .. "  " .. time
        local line0 = #lines - 1
        line_to_row[#lines] = row

        if section == "ARCHIVED" then
          highlights[#highlights + 1] =
            { line = line0, col_start = 0, col_end = -1, hl_group = "AgentFleetArchived" }
        else
          local state_start = #("  " .. marker .. " ")
          highlights[#highlights + 1] = {
            line = line0,
            col_start = state_start,
            col_end = state_start + #state,
            hl_group = STATE_HL[state] or "AgentFleetNew",
          }
          local time_start = #("  " .. marker .. " " .. state_col .. "  " .. name_col .. "  ")
          highlights[#highlights + 1] = {
            line = line0,
            col_start = time_start,
            col_end = time_start + #time,
            hl_group = "AgentFleetTime",
          }
        end
      end
    end
  end

  lines[#lines + 1] = ""
  local legend = {
    "  <CR> open \u{00b7} a new \u{00b7} i prompt \u{00b7} r rename \u{00b7} s stop",
    "  d done \u{00b7} x archive \u{00b7} A archived \u{00b7} R refresh",
  }
  for _, l in ipairs(legend) do
    lines[#lines + 1] = l
    highlights[#highlights + 1] =
      { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AgentFleetTime" }
  end

  return { lines = lines, highlights = highlights, line_to_row = line_to_row }
end

function M.done_candidates(cwd)
  local rows = M.rows({ cwd = cwd or vim.fn.getcwd() })
  local result = {}
  for _, row in ipairs(rows) do
    if not row.done then
      result[#result + 1] = row
    end
  end
  return result
end

function M.archive_candidates(cwd)
  return M.rows({ cwd = cwd or vim.fn.getcwd(), include_archived = true })
end

return M
