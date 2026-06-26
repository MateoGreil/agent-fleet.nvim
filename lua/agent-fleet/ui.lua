local M = {}

local HL_LINKS = {
  AgentFleetWorking = "DiagnosticInfo",
  AgentFleetIdle = "Normal",
  AgentFleetStopped = "Comment",
  AgentFleetError = "DiagnosticError",
  AgentFleetNew = "DiagnosticHint",
  AgentFleetUnknown = "NonText",
  AgentFleetDone = "DiagnosticOk",
  AgentFleetArchived = "Comment",
  AgentFleetHeader = "Title",
  AgentFleetTime = "Comment",
}

local state = {
  bufnr = nil,
  ns = nil,
  show_archived = false,
  line_to_row = {},
}

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

  local ns = namespace()
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, spec.lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, h in ipairs(spec.highlights) do
    local end_col = h.col_end
    if end_col == -1 then
      end_col = #spec.lines[h.line + 1]
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, h.line, h.col_start, {
      end_col = end_col,
      hl_group = h.hl_group,
    })
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  state.line_to_row = spec.line_to_row
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
  render_into(bufnr)
end

return M
