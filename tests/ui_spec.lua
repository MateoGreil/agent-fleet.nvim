vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local ui = require("agent-fleet.ui")
local roster = require("agent-fleet.roster")
local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")
config.setup({ sessions_dir = TMP })

local function win_opt(win, name)
  return vim.api.nvim_get_option_value(name, { win = win })
end

local function buf_opt(bufnr, name)
  return vim.api.nvim_get_option_value(name, { buf = bufnr })
end

local function line_of_id(line_to_row, id)
  for lnum, row in pairs(line_to_row) do
    if row.id == id then
      return lnum
    end
  end
  return nil
end

-- Case 1: define_highlights defines links and never stomps a user def
vim.api.nvim_set_hl(0, "AgentFleetWorking", { fg = 0xff0000 })
ui.define_highlights()
local working = vim.api.nvim_get_hl(0, { name = "AgentFleetWorking" })
check("define user AgentFleetWorking survives", working.fg == 0xff0000 and working.link == nil)
local header = vim.api.nvim_get_hl(0, { name = "AgentFleetHeader" })
check("define AgentFleetHeader links to Title", header.link == "Title")
local arch = vim.api.nvim_get_hl(0, { name = "AgentFleetArchived" })
check("define AgentFleetArchived links to Comment", arch.link == "Comment")
local time = vim.api.nvim_get_hl(0, { name = "AgentFleetTime" })
check("define AgentFleetTime links to Comment", time.link == "Comment")

-- Case 2: open in a populated project
local PROJ = TMP .. "/proj"
vim.fn.mkdir(PROJ, "p")
vim.fn.chdir(PROJ)
local idA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local idB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
roster.add({ id = idA, type = "pi", name = "alpha", cwd = PROJ, created_at = 1000 })
roster.add({ id = idB, type = "pi", name = "beta", cwd = PROJ, created_at = 2000 })

ui.open()
local bufnr = vim.api.nvim_get_current_buf()
check("open sets current buffer to a board buffer", vim.api.nvim_buf_is_valid(bufnr))
check("open buffer filetype agentfleet", buf_opt(bufnr, "filetype") == "agentfleet")
check("open buffer buftype nofile", buf_opt(bufnr, "buftype") == "nofile")
check("open buffer bufhidden wipe", buf_opt(bufnr, "bufhidden") == "wipe")
check("open buffer not modifiable", buf_opt(bufnr, "modifiable") == false)
check("open buffer not listed", buf_opt(bufnr, "buflisted") == false)
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
check("open buffer non-empty", #lines > 0 and lines[1] ~= "")
local function lines_have(ls, needle)
  for _, l in ipairs(ls) do
    if l:find(needle, 1, true) then
      return true
    end
  end
  return false
end
check("open buffer mentions an agent name", lines_have(lines, "alpha"))

-- Case 2b: the AGENT-FLEET banner title sits at the top
check("board first line is the banner", lines[1]:find("\u{2588}", 1, true) ~= nil)
check("board shows the .nvim subtitle", lines_have(lines, ".nvim"))

local win = vim.api.nvim_get_current_win()
check("open window number off", win_opt(win, "number") == false)
check("open window relativenumber off", win_opt(win, "relativenumber") == false)
check("open window wrap off", win_opt(win, "wrap") == false)
check("open window cursorline on", win_opt(win, "cursorline") == true)

-- Case 3: highlights painted into the buffer (extmarks exist)
local ns = vim.api.nvim_create_namespace("agent_fleet_board")
local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
check("open paints extmarks", #marks > 0)

-- Case 4: refresh preserves cursor by row identity across reorder.
-- Uses the live board mapping (ui._state.line_to_row), which accounts for the
-- banner offset, so it is independent of the pure render's line numbers.
local lineA = line_of_id(ui._state.line_to_row, idA)
check("refresh setup found row A", lineA ~= nil)
vim.api.nvim_win_set_cursor(win, { lineA, 0 })
-- Reorder: mark B done so it leaves the IDLE section; A shifts up.
roster.mark_done(idB)
ui.refresh()
local cur = vim.api.nvim_win_get_cursor(win)[1]
local cur_row = ui._state.line_to_row[cur]
check("refresh cursor follows row A after reorder", cur_row ~= nil and cur_row.id == idA)

-- Case 5: the landed line maps to a real content row
check("refresh landed on a content row", cur_row ~= nil and cur_row.id == idA)

-- Case 6: empty state in a fresh project (board buffer wiped on enew, reopened)
local EMPTY = TMP .. "/empty"
vim.fn.mkdir(EMPTY, "p")
vim.fn.chdir(EMPTY)
vim.cmd("enew")
ui.open()
local ebuf = vim.api.nvim_get_current_buf()
local elines = vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)
check("empty state placeholder", lines_have(elines, "No agents in this directory."))
check("empty state title", lines_have(elines, "agent-fleet"))

-- Case 7: board.refresh_ms default present
check("board.refresh_ms default is 2000", config.get().board.refresh_ms == 2000)

-- Case 8: open starts a libuv timer stored in module state
check("open starts a timer handle", ui._state.timer ~= nil)

-- Case 9: TermClose autocmd registered under the named augroup
local term_autocmds = vim.api.nvim_get_autocmds({ event = "TermClose", group = "AgentFleetBoardTermClose" })
check("TermClose autocmd registered", #term_autocmds >= 1)

-- Case 10: a manual refresh reflects current roster state (what TermClose triggers)
local idC = "cccccccc-cccc-cccc-cccc-cccccccccccc"
roster.add({ id = idC, type = "pi", name = "gamma", cwd = EMPTY, created_at = 3000 })
ui.refresh()
local rlines = vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)
check("refresh reflects newly added agent", lines_have(rlines, "gamma"))

-- Case 11: BufWipeout stops the timer and clears module state, no error
local ok_wipe = pcall(vim.api.nvim_buf_delete, ebuf, { force = true })
vim.wait(50, function() return false end)
check("wipeout did not error", ok_wipe)
check("wipeout clears timer handle", ui._state.timer == nil)
check("wipeout clears bufnr", ui._state.bufnr == nil)

-- Case 11b: BufWipeout resets show_archived to its default
vim.cmd("enew")
ui.open()
local abuf = vim.api.nvim_get_current_buf()
ui._state.show_archived = true
vim.api.nvim_buf_delete(abuf, { force = true })
vim.wait(50, function() return false end)
check("wipeout resets show_archived to false", ui._state.show_archived == false)

-- Case 12: the timer actually ticks a refresh. Uses a short configured
-- interval and a generous wait budget (250ms for a 50ms timer => ~4 ticks),
-- so it is not sensitive to scheduler jitter (passing needs only >=1 tick).
config.setup({ sessions_dir = TMP, board = { refresh_ms = 50 } })
vim.cmd("enew")
ui.open()
local orig_refresh = ui.refresh
local tick_count = 0
ui.refresh = function(...)
  tick_count = tick_count + 1
  return orig_refresh(...)
end
vim.wait(250, function() return false end)
ui.refresh = orig_refresh
check("timer ticks at least one refresh", tick_count >= 1)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
