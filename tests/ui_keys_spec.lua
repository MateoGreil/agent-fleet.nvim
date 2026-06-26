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

local PROJ = TMP .. "/proj"
vim.fn.mkdir(PROJ, "p")
vim.fn.chdir(PROJ)

local idA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local idB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local idC = "cccccccc-cccc-cccc-cccc-cccccccccccc"
roster.add({ id = idA, type = "pi", name = "alpha", cwd = PROJ, created_at = 1000 })
roster.add({ id = idB, type = "pi", name = "beta", cwd = PROJ, created_at = 2000 })
roster.add({ id = idC, type = "pi", name = "gamma", cwd = PROJ, created_at = 3000 })
roster.set_archived(idC, true)

ui.open()
local bufnr = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()

local function keymap_callbacks()
  local map = {}
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    map[km.lhs] = km.callback
  end
  return map
end

local function buf_lines()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function line_with(name)
  for i, l in ipairs(buf_lines()) do
    if l:find(name, 1, true) then
      return i
    end
  end
  return nil
end

local function lines_have(needle)
  for _, l in ipairs(buf_lines()) do
    if l:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function cursor_to(name)
  local ln = line_with(name)
  vim.api.nvim_win_set_cursor(win, { ln, 0 })
  return ln
end

local cb = keymap_callbacks()

-- Case 1: every required key is bound to a callback
for _, key in ipairs({ "<CR>", "d", "x", "r", "s", "A", "R", "gr" }) do
  check("keymap bound: " .. key, type(cb[key]) == "function")
end
check("launch key a bound", type(cb["a"]) == "function")
check("launch key i bound", type(cb["i"]) == "function")

-- Launch keymaps: stub agent-fleet.launch and vim.ui.input to capture intent
local af = require("agent-fleet")
local orig_launch = af.launch
local launch_opts
local launch_calls = 0
af.launch = function(opts)
  launch_calls = launch_calls + 1
  launch_opts = opts
  return nil
end

-- a -> launch with no prompt
launch_opts = nil
launch_calls = 0
cb["a"]()
check("a calls launch once", launch_calls == 1)
check("a calls launch with no prompt", launch_opts ~= nil and launch_opts.prompt == nil)

local orig_input = vim.ui.input

-- i -> launch with the typed prompt
launch_opts = nil
launch_calls = 0
vim.ui.input = function(_, on_confirm)
  on_confirm("  do the thing  ")
end
cb["i"]()
check("i calls launch once", launch_calls == 1)
check("i passes trimmed prompt", launch_opts ~= nil and launch_opts.prompt == "do the thing")

-- i with empty input -> launch not called
launch_calls = 0
vim.ui.input = function(_, on_confirm)
  on_confirm("   ")
end
cb["i"]()
check("i with blank input does not launch", launch_calls == 0)

-- i cancelled (nil) -> launch not called
launch_calls = 0
vim.ui.input = function(_, on_confirm)
  on_confirm(nil)
end
cb["i"]()
check("i cancelled does not launch", launch_calls == 0)

vim.ui.input = orig_input
af.launch = orig_launch

-- Case 2: row_under_cursor returns the right row on a content line
cursor_to("alpha")
local r = ui.row_under_cursor()
check("row_under_cursor returns alpha row", r ~= nil and r.id == idA)

-- Case 3: row_under_cursor is nil on a header / title line
vim.api.nvim_win_set_cursor(win, { 1, 0 })
check("row_under_cursor nil on header line", ui.row_under_cursor() == nil)

-- Case 4: d marks the row under cursor done and re-renders
cursor_to("alpha")
cb["d"]()
check("d marks roster done", roster.get(idA) ~= nil and roster.get(idA).done == true)
check("d re-renders with DONE section", lines_have("DONE"))
check("d keeps alpha visible after re-render", line_with("alpha") ~= nil)

-- Case 5: x toggles archived state of the row under cursor
cursor_to("beta")
cb["x"]()
check("x archives beta", roster.get(idB) ~= nil and roster.get(idB).archived == true)
check("x hides beta from default view", line_with("beta") == nil)

-- Case 6: A toggles archived-section visibility; archived rows then appear
check("gamma hidden before A", line_with("gamma") == nil)
cb["A"]()
check("A reveals archived gamma", line_with("gamma") ~= nil)
local gline = cursor_to("gamma")
local gr = ui.row_under_cursor()
check("revealed archived row resolves via line_to_row", gr ~= nil and gr.id == idC)
cb["A"]()
check("A again hides archived gamma", line_with("gamma") == nil)

-- Case 7: s on a non-live row is a safe no-op (notify only, no state change)
cursor_to("alpha")
local before = roster.get(idA)
local ok = pcall(function()
  cb["s"]()
end)
check("s on non-live row does not error", ok == true)
check("s on non-live row leaves roster unchanged", roster.get(idA).done == before.done)
check("s on non-live row keeps row visible", line_with("alpha") ~= nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
