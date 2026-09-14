vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local af = require("agent-fleet")

local orig_launch = af.launch
local orig_input = vim.ui.input

local launch_calls
local launch_opts
local input_calls
local input_prompt
local input_answer

local function reset(answer)
  launch_calls = 0
  launch_opts = nil
  input_calls = 0
  input_prompt = nil
  input_answer = answer
  af.launch = function(opts)
    launch_calls = launch_calls + 1
    launch_opts = opts
    return nil
  end
  vim.ui.input = function(opts, on_confirm)
    input_calls = input_calls + 1
    input_prompt = opts.prompt
    on_confirm(input_answer)
  end
end

local function restore()
  af.launch = orig_launch
  vim.ui.input = orig_input
end

-- interactive() in prompt mode: asks for a prompt, launches with it
config.setup({ agents = { pi = {} } })
reset("  do the thing  ")
require("agent-fleet.launch_input").interactive()
check("prompt mode asks 'New agent prompt:'", input_prompt == "New agent prompt: ")
check("prompt mode launches once", launch_calls == 1)
check("prompt mode passes trimmed prompt", launch_opts ~= nil and launch_opts.prompt == "do the thing")
check("prompt mode passes no name", launch_opts ~= nil and launch_opts.name == nil)

-- interactive() in name mode: asks for a name, launches with it, no prompt
config.setup({ agents = { pi = {} }, launch_input = "name" })
reset("  fix-login  ")
require("agent-fleet.launch_input").interactive()
check("name mode asks 'New agent name:'", input_prompt == "New agent name: ")
check("name mode launches once", launch_calls == 1)
check("name mode passes trimmed name", launch_opts ~= nil and launch_opts.name == "fix-login")
check("name mode passes no prompt", launch_opts ~= nil and launch_opts.prompt == nil)

-- interactive() in name mode: blank answer cancels
reset("   ")
require("agent-fleet.launch_input").interactive()
check("name mode blank answer does not launch", launch_calls == 0)

-- interactive() in name mode: cancelled (nil) does not launch
reset(nil)
require("agent-fleet.launch_input").interactive()
check("name mode cancelled does not launch", launch_calls == 0)

-- from_args in prompt mode: args become the prompt, no input
config.setup({ agents = { pi = {} } })
reset(nil)
require("agent-fleet.launch_input").from_args("hello world")
check("from_args prompt mode launches with prompt", launch_opts ~= nil and launch_opts.prompt == "hello world")
check("from_args prompt mode asks nothing", input_calls == 0)

-- from_args in name mode: args become the name, no input
config.setup({ agents = { pi = {} }, launch_input = "name" })
reset(nil)
require("agent-fleet.launch_input").from_args("fix login page")
check("from_args name mode launches with name", launch_opts ~= nil and launch_opts.name == "fix login page")
check("from_args name mode asks nothing", input_calls == 0)

-- from_args with blank args falls into the interactive flow of the mode
config.setup({ agents = { pi = {} }, launch_input = "name" })
reset("named")
require("agent-fleet.launch_input").from_args("   ")
check("from_args blank falls back to input", input_calls == 1)
check("from_args blank launches with typed name", launch_opts ~= nil and launch_opts.name == "named")

-- invalid launch_input behaves as prompt mode
config.setup({ agents = { pi = {} }, launch_input = "bogus" })
reset("typed")
require("agent-fleet.launch_input").interactive()
check("invalid launch_input treated as prompt mode", input_prompt == "New agent prompt: ")

restore()

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
