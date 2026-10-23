vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local af = require("agent-fleet")

local orig_launch = af.launch
local orig_input = vim.ui.input
local orig_select = vim.ui.select
local orig_mode = vim.api.nvim_get_mode
local orig_now = vim.uv.now
local orig_defer_fn = vim.defer_fn

local launch_calls
local launch_opts
local input_calls
local input_mode_at_call

-- Simulates a picker backend whose confirm callback fires while the editor is
-- still in terminal mode, with the teardown ("stopinsert") landing one tick
-- later -- the exact shape of fzf-lua's ui.select teardown.
local function install_select(mode_at_choice, teardown_mode)
  vim.ui.select = function(_, _, on_choice)
    vim.api.nvim_get_mode = function()
      return { mode = mode_at_choice }
    end
    on_choice("pi")
    vim.api.nvim_get_mode = function()
      return { mode = teardown_mode }
    end
  end
end

local function install_input()
  input_calls = 0
  input_mode_at_call = nil
  vim.ui.input = function(_, on_confirm)
    input_calls = input_calls + 1
    input_mode_at_call = vim.api.nvim_get_mode().mode
    on_confirm("fix-login")
  end
end

local function install_launch()
  launch_calls = 0
  launch_opts = nil
  af.launch = function(opts)
    launch_calls = launch_calls + 1
    launch_opts = opts
    return nil
  end
end

local function restore()
  af.launch = orig_launch
  vim.ui.input = orig_input
  vim.ui.select = orig_select
  vim.api.nvim_get_mode = orig_mode
  vim.uv.now = orig_now
  vim.defer_fn = orig_defer_fn
end

-- interactive_pick: the input must not open while the picker teardown is
-- still switching the editor out of terminal mode.
config.setup({ agents = { pi = {} }, default_agent = "pi", launch_input = "name" })
install_select("t", "n")
install_input()
install_launch()
require("agent-fleet.launch_input").interactive_pick()
check("pick->input: input not opened while in terminal mode", input_calls == 0)
vim.wait(2000, function()
  return input_calls > 0
end, 10)
check("pick->input: input opened after teardown settled", input_calls == 1)
check("pick->input: input opened outside terminal mode", input_mode_at_call ~= "t" and input_mode_at_call ~= "nt")
check(
  "pick->input: launch used picked agent and typed name",
  launch_calls == 1 and launch_opts ~= nil and launch_opts.agent == "pi" and launch_opts.name == "fix-login"
)

-- pick_from_args with a value: the launch itself must also wait for the
-- teardown, or the agent's startinsert gets clobbered out of terminal mode.
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
install_select("t", "n")
launch_calls = 0
launch_opts = nil
input_calls = 0
local launch_mode_at_call = nil
af.launch = function(opts)
  launch_calls = launch_calls + 1
  launch_opts = opts
  launch_mode_at_call = vim.api.nvim_get_mode().mode
  return nil
end
require("agent-fleet.launch_input").pick_from_args("fix auth")
check("pick->launch: launch not run while in terminal mode", launch_calls == 0)
vim.wait(2000, function()
  return launch_calls > 0
end, 10)
check("pick->launch: launch ran after teardown settled", launch_calls == 1)
check("pick->launch: launch ran outside terminal mode", launch_mode_at_call ~= "t" and launch_mode_at_call ~= "nt")
check(
  "pick->launch: launch used picked agent and value",
  launch_opts ~= nil and launch_opts.agent == "pi" and launch_opts.prompt == "fix auth"
)

-- Deadline fallback: if terminal mode never settles (e.g. launched from a
-- user terminal), the continuation still runs instead of hanging forever.
config.setup({ agents = { pi = {} }, default_agent = "pi", launch_input = "name" })
vim.ui.select = function(_, _, on_choice)
  vim.api.nvim_get_mode = function()
    return { mode = "t" }
  end
  on_choice("pi")
end
install_input()
install_launch()
require("agent-fleet.launch_input").interactive_pick()
check("stuck terminal: input not opened immediately", input_calls == 0)
local opened = vim.wait(3000, function()
  return input_calls > 0
end, 10)
check("stuck terminal: input opened at deadline fallback", opened and input_calls == 1)

-- Non-terminal pickers keep the synchronous behavior (native select, snacks).
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi", launch_input = "name" })
vim.api.nvim_get_mode = orig_mode
vim.ui.select = function(items, opts, on_choice)
  on_choice("claude")
  return #items, opts
end
install_input()
install_launch()
require("agent-fleet.launch_input").interactive_pick()
check(
  "non-terminal picker: input opened synchronously",
  input_calls == 1 and input_mode_at_call ~= "t" and input_mode_at_call ~= "nt"
)
check(
  "non-terminal picker: launch synchronous with picked agent",
  launch_calls == 1 and launch_opts ~= nil and launch_opts.agent == "claude"
)

restore()

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
