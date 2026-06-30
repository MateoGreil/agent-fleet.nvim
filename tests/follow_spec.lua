vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

-- A buffer with more lines than fit on screen, shown in two windows.
vim.cmd("enew")
local buf = vim.api.nvim_get_current_buf()
local lines = {}
for i = 1, 300 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
local line_count = vim.api.nvim_buf_line_count(buf)

vim.cmd("vsplit")
local wins = vim.api.nvim_list_wins()
local w_a, w_b = wins[1], wins[2]

-- Scroll both windows to the top, then focus w_a (leaving w_b unfocused).
vim.api.nvim_win_set_cursor(w_a, { 1, 0 })
vim.api.nvim_win_set_cursor(w_b, { 1, 0 })
vim.api.nvim_set_current_win(w_a)

agent.follow_to_bottom(buf)

local info_a = vim.fn.getwininfo(w_a)[1]
local info_b = vim.fn.getwininfo(w_b)[1]

check("unfocused window pinned to bottom", info_b.botline >= line_count - 1)
check("focused window left untouched (still at top)", info_a.topline == 1)

-- Invalid / nil buffer must be a no-op, not an error.
local ok = pcall(agent.follow_to_bottom, nil)
check("nil bufnr is a no-op", ok)
ok = pcall(agent.follow_to_bottom, 999999)
check("invalid bufnr is a no-op", ok)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
