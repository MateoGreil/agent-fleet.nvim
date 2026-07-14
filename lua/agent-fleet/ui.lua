local M = {}

local HL_LINKS = {
  AgentFleetWorking = "DiagnosticInfo",
  AgentFleetIdle = "Normal",
  AgentFleetStopped = "Comment",
  AgentFleetError = "DiagnosticError",
  AgentFleetNew = "DiagnosticHint",
  AgentFleetUnknown = "NonText",
  AgentFleetArchived = "Comment",
  AgentFleetHeader = "Title",
  AgentFleetTime = "Comment",
}

local state = {
  bufnr = nil,
  ns = nil,
  show_archived = false,
  line_to_row = {},
  timer = nil,
}

M._state = state

local BANNER = {
  " ██   ███ ████ █  █ ████      ████ █    ████ ████ ████",
  "█  █ █    █    ██ █  █        █    █    █    █     █  ",
  "████ █ ██ ███  █ ██  █    ██  ███  █    ███  ███   █  ",
  "█  █ █  █ █    █  █  █        █    █    █    █     █  ",
  "█  █  ███ ████ █  █  █        █    ████ ████ ████  █  ",
}
local BANNER_SUBTITLE = string.rep(" ", 49) .. ".nvim"

function M.define_highlights()
  for name, target in pairs(HL_LINKS) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

local function namespace()
  if not state.ns then
    state.ns = vim.api.nvim_create_namespace("agent_fleet_board")
  end
  return state.ns
end

local function window_showing(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

local function render_into(bufnr)
  local board = require("agent-fleet.board")
  local cwd = vim.fn.getcwd()
  local rows = board.rows({ cwd = cwd, include_archived = true })

  local archived_count = 0
  for _, row in ipairs(rows) do
    if row.archived then
      archived_count = archived_count + 1
    end
  end

  local spec = board.render(rows, {
    now_ms = os.time() * 1000,
    cwd = cwd,
    show_archived = state.show_archived,
    archived_count = archived_count,
  })

  local lines = {}
  for _, l in ipairs(BANNER) do
    lines[#lines + 1] = l
  end
  lines[#lines + 1] = BANNER_SUBTITLE
  lines[#lines + 1] = ""
  local offset = #lines
  for _, l in ipairs(spec.lines) do
    lines[#lines + 1] = l
  end

  local ns = namespace()
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for i, l in ipairs(BANNER) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
      end_col = #l,
      hl_group = "AgentFleetHeader",
    })
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, #BANNER, #BANNER_SUBTITLE - #".nvim", {
    end_col = #BANNER_SUBTITLE,
    hl_group = "AgentFleetTime",
  })
  for _, h in ipairs(spec.highlights) do
    local end_col = h.col_end
    if end_col == -1 then
      end_col = #spec.lines[h.line + 1]
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, h.line + offset, h.col_start, {
      end_col = end_col,
      hl_group = h.hl_group,
    })
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  state.line_to_row = {}
  for lnum, row in pairs(spec.line_to_row) do
    state.line_to_row[lnum + offset] = row
  end
end

local function nearest_content_line(target)
  local best, best_dist
  for lnum in pairs(state.line_to_row) do
    local dist = math.abs(lnum - target)
    if not best_dist or dist < best_dist then
      best_dist = dist
      best = lnum
    end
  end
  return best or 1
end

function M.refresh()
  local bufnr = state.bufnr
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  local win = window_showing(bufnr)
  if not win then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
  local prev_row = state.line_to_row[cursor_line]
  local prev_id = prev_row and prev_row.id or nil

  render_into(bufnr)

  local target
  if prev_id then
    for lnum, row in pairs(state.line_to_row) do
      if row.id == prev_id then
        target = lnum
        break
      end
    end
  end
  target = target or nearest_content_line(cursor_line)
  target = math.min(target, vim.api.nvim_buf_line_count(bufnr))
  pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
end

function M.row_under_cursor()
  local bufnr = state.bufnr
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  local win = window_showing(bufnr)
  if not win then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return state.line_to_row[line]
end

function M.rows_in_range(line1, line2)
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local rows = {}
  local seen = {}
  for lnum = line1, line2 do
    local row = state.line_to_row[lnum]
    if row and not seen[row.id] then
      seen[row.id] = true
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function notify(msg)
  vim.notify("agent-fleet: " .. msg, vim.log.levels.INFO)
end

local function handle_enter()
  local row = M.row_under_cursor()
  if not row then
    return
  end
  require("agent-fleet.agent").resume_session({ id = row.id, cwd = row.cwd, type = row.type })
end

local function toggle_done_rows(rows)
  if #rows == 0 then
    return
  end
  local actions = require("agent-fleet.actions")
  local done, undone = 0, 0
  for _, row in ipairs(rows) do
    if actions.done(row) then
      done = done + 1
    else
      undone = undone + 1
    end
  end
  M.refresh()
  if #rows == 1 then
    notify((done == 1 and "marked done" or "marked not done") .. " \u{2014} " .. rows[1].name)
    return
  end
  local parts = {}
  if done > 0 then
    parts[#parts + 1] = "done " .. done
  end
  if undone > 0 then
    parts[#parts + 1] = "not done " .. undone
  end
  notify(table.concat(parts, ", "))
end

function M.done_range(line1, line2)
  toggle_done_rows(M.rows_in_range(line1, line2))
end

local function handle_done()
  local row = M.row_under_cursor()
  if not row then
    return
  end
  toggle_done_rows({ row })
end

local function visual_line_range()
  local a = vim.fn.line("v")
  local b = vim.fn.line(".")
  if a > b then
    a, b = b, a
  end
  return a, b
end

local function exit_visual()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
    "n",
    false
  )
end

local function handle_done_visual()
  local line1, line2 = visual_line_range()
  exit_visual()
  M.done_range(line1, line2)
end

local function archive_rows(rows)
  if #rows == 0 then
    return
  end
  local actions = require("agent-fleet.actions")
  local archived, unarchived = 0, 0
  for _, row in ipairs(rows) do
    if actions.archive(row) then
      archived = archived + 1
    else
      unarchived = unarchived + 1
    end
  end
  M.refresh()
  if #rows == 1 then
    notify((archived == 1 and "archived" or "unarchived") .. " \u{2014} " .. rows[1].name)
    return
  end
  local parts = {}
  if archived > 0 then
    parts[#parts + 1] = "archived " .. archived
  end
  if unarchived > 0 then
    parts[#parts + 1] = "unarchived " .. unarchived
  end
  notify(table.concat(parts, ", "))
end

function M.archive_range(line1, line2)
  archive_rows(M.rows_in_range(line1, line2))
end

local function handle_archive()
  local row = M.row_under_cursor()
  if not row then
    return
  end
  archive_rows({ row })
end

local function handle_archive_visual()
  local line1, line2 = visual_line_range()
  exit_visual()
  M.archive_range(line1, line2)
end

local function handle_rename()
  local row = M.row_under_cursor()
  if not row then
    return
  end
  vim.ui.input({ prompt = "Rename agent: ", default = row.name }, function(input)
    input = input and vim.trim(input)
    if input and input ~= "" then
      require("agent-fleet.actions").rename(row, input)
      M.refresh()
      notify("renamed \u{2014} " .. input)
    end
  end)
end

local function stop_rows(rows)
  if #rows == 0 then
    return
  end
  local actions = require("agent-fleet.actions")
  local stopped = 0
  local last
  for _, row in ipairs(rows) do
    if row.live then
      actions.close_live(row)
      stopped = stopped + 1
      last = row
    end
  end
  if stopped == 0 then
    if #rows == 1 then
      notify("not running \u{2014} " .. rows[1].name)
    else
      notify("no running agents in selection")
    end
    return
  end
  M.refresh()
  if stopped == 1 then
    notify("stopped \u{2014} " .. last.name)
  else
    notify("stopped \u{2014} " .. stopped .. " agents")
  end
end

function M.stop_range(line1, line2)
  stop_rows(M.rows_in_range(line1, line2))
end

local function handle_stop()
  local row = M.row_under_cursor()
  if not row then
    return
  end
  stop_rows({ row })
end

local function handle_stop_visual()
  local line1, line2 = visual_line_range()
  exit_visual()
  M.stop_range(line1, line2)
end

local function handle_toggle_archived()
  state.show_archived = not state.show_archived
  M.refresh()
end

local function handle_launch()
  require("agent-fleet").launch({})
end

local function handle_launch_prompt()
  vim.ui.input({ prompt = "New agent prompt: " }, function(input)
    input = input and vim.trim(input)
    if input and input ~= "" then
      require("agent-fleet").launch({ prompt = input })
    end
  end)
end

local function set_keymaps(bufnr)
  local opts = { buffer = bufnr, nowait = true, silent = true, noremap = true }
  vim.keymap.set("n", "<CR>", handle_enter, opts)
  vim.keymap.set("n", "d", handle_done, opts)
  vim.keymap.set("x", "d", handle_done_visual, opts)
  vim.keymap.set("n", "x", handle_archive, opts)
  vim.keymap.set("x", "x", handle_archive_visual, opts)
  vim.keymap.set("n", "r", handle_rename, opts)
  vim.keymap.set("n", "s", handle_stop, opts)
  vim.keymap.set("x", "s", handle_stop_visual, opts)
  vim.keymap.set("n", "a", handle_launch, opts)
  vim.keymap.set("n", "i", handle_launch_prompt, opts)
  vim.keymap.set("n", "A", handle_toggle_archived, opts)
  vim.keymap.set("n", "R", M.refresh, opts)
  vim.keymap.set("n", "gr", M.refresh, opts)
end

local function stop_timer()
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
    state.timer = nil
  end
end

local function start_timer()
  stop_timer()
  local interval = require("agent-fleet.config").get().board.refresh_ms
  local timer = vim.uv.new_timer()
  state.timer = timer
  timer:start(interval, interval, function()
    vim.schedule(function()
      local bufnr = state.bufnr
      if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        stop_timer()
        return
      end
      if window_showing(bufnr) then
        M.refresh()
      end
    end)
  end)
end

local function set_autocmds(bufnr)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      stop_timer()
      state.bufnr = nil
      state.line_to_row = {}
      state.show_archived = false
    end,
  })

  local group = vim.api.nvim_create_augroup("AgentFleetBoardTermClose", { clear = true })
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function()
      local b = state.bufnr
      if b and vim.api.nvim_buf_is_valid(b) and window_showing(b) then
        M.refresh()
      end
    end,
  })
end

function M.open()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local win = window_showing(state.bufnr)
    if win then
      vim.api.nvim_set_current_win(win)
      M.refresh()
      return
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "agentfleet", { buf = bufnr })
  state.bufnr = bufnr

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  M.define_highlights()
  set_keymaps(bufnr)
  set_autocmds(bufnr)
  render_into(bufnr)
  start_timer()
end

return M
