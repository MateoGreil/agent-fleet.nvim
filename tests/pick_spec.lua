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

local launch_calls
local launch_opts
local input_calls
local input_prompt
local input_answer
local select_calls
local select_items
local select_format_item
local select_choice

local function reset(select_ch, input_ans)
  launch_calls = 0
  launch_opts = nil
  input_calls = 0
  input_prompt = nil
  input_answer = input_ans
  select_calls = 0
  select_items = nil
  select_format_item = nil
  select_choice = select_ch
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
  vim.ui.select = function(items, opts, on_choice)
    select_calls = select_calls + 1
    select_items = vim.deepcopy(items)
    select_format_item = opts.format_item
    on_choice(select_choice)
  end
end

local function restore()
  af.launch = orig_launch
  vim.ui.input = orig_input
  vim.ui.select = orig_select
end

-- Test 1: Single declared agent: picker still opens, one item, its label is `<key> (default)`
config.setup({ agents = { pi = {} }, default_agent = "pi" })
reset("pi", nil)
require("agent-fleet.launch_input").interactive_pick()
check(
  "single agent: picker has one item",
  select_calls == 1 and select_items ~= nil and #select_items == 1
)
check("single agent: item is 'pi'", select_items ~= nil and select_items[1] == "pi")
check(
  "single agent: format renders with (default)",
  select_format_item ~= nil and select_format_item("pi") == "pi (default)"
)

-- Test 2: Multiple agents (pi default, claude, opencode declared in that order)
-- items are keys pi, claude, opencode in that order (default first, rest alphabetical)
config.setup({
  agents = { pi = {}, claude = {}, opencode = {} },
  default_agent = "pi",
})
reset("claude", nil)
require("agent-fleet.launch_input").interactive_pick()
check(
  "multiple agents: picker called",
  select_calls == 1
)
check(
  "multiple agents: three items",
  select_items ~= nil and #select_items == 3
)
check(
  "multiple agents: order is pi, claude, opencode",
  select_items ~= nil
    and select_items[1] == "pi"
    and select_items[2] == "claude"
    and select_items[3] == "opencode"
)
check(
  "multiple agents: format_item renders default",
  select_format_item ~= nil and select_format_item("pi") == "pi (default)"
)
check(
  "multiple agents: format_item renders non-default",
  select_format_item ~= nil and select_format_item("claude") == "claude"
)

-- Test 2b: nil default_agent (multiple agents declared, none marked default)
config.setup({ agents = { pi = {}, claude = {} } })
reset("claude", nil)
require("agent-fleet.launch_input").pick_from_args("fix auth")
check(
  "nil default: picker called without error",
  select_calls == 1
)
check(
  "nil default: items are both keys, alphabetical, unmarked",
  select_items ~= nil
    and #select_items == 2
    and select_items[1] == "claude"
    and select_items[2] == "pi"
)
check(
  "nil default: format_item never renders (default)",
  select_format_item ~= nil
    and select_format_item("claude") == "claude"
    and select_format_item("pi") == "pi"
)
check(
  "nil default: pick_from_args launches with picked agent and prompt",
  launch_opts ~= nil
    and launch_opts.agent == "claude"
    and launch_opts.prompt == "fix auth"
)

-- Test 3: pick_from_args("fix auth") in prompt mode
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset("claude", nil)
require("agent-fleet.launch_input").pick_from_args("fix auth")
check(
  "pick_from_args prompt: launches with agent and prompt",
  launch_opts ~= nil
    and launch_opts.agent == "claude"
    and launch_opts.prompt == "fix auth"
)
check("pick_from_args prompt: no input asked", input_calls == 0)

-- Test 4: pick_from_args("fix auth") in name mode
config.setup(
  { agents = { pi = {}, claude = {} }, default_agent = "pi", launch_input = "name" }
)
reset("claude", nil)
require("agent-fleet.launch_input").pick_from_args("fix auth")
check(
  "pick_from_args name: launches with agent and name",
  launch_opts ~= nil
    and launch_opts.agent == "claude"
    and launch_opts.name == "fix auth"
)
check("pick_from_args name: no input asked", input_calls == 0)

-- Test 5: interactive_pick() in prompt mode: select pi -> input asked -> launch
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset("pi", "do the thing")
require("agent-fleet.launch_input").interactive_pick()
check(
  "interactive_pick prompt: input asked with correct prompt",
  input_prompt == "New agent prompt: "
)
check(
  "interactive_pick prompt: launches with agent and typed prompt",
  launch_opts ~= nil
    and launch_opts.agent == "pi"
    and launch_opts.prompt == "do the thing"
)

-- Test 6: interactive_pick() in name mode: select pi -> input asked -> launch
config.setup(
  { agents = { pi = {}, claude = {} }, default_agent = "pi", launch_input = "name" }
)
reset("pi", "fix-login")
require("agent-fleet.launch_input").interactive_pick()
check(
  "interactive_pick name: input asked with correct prompt",
  input_prompt == "New agent name: "
)
check(
  "interactive_pick name: launches with agent and typed name",
  launch_opts ~= nil
    and launch_opts.agent == "pi"
    and launch_opts.name == "fix-login"
)

-- Test 7: Picker cancelled (on_choice(nil)): no launch, no input asked
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset(nil, nil)
require("agent-fleet.launch_input").interactive_pick()
check("picker cancelled interactive_pick: no launch", launch_calls == 0)
check("picker cancelled interactive_pick: no input asked", input_calls == 0)

config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset(nil, nil)
require("agent-fleet.launch_input").pick_from_args("x")
check("picker cancelled pick_from_args: no launch", launch_calls == 0)
check("picker cancelled pick_from_args: no input asked", input_calls == 0)

-- Test 8: Input cancelled/blank after a successful pick
config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset("pi", nil)
require("agent-fleet.launch_input").interactive_pick()
check("input cancelled after pick: no launch", launch_calls == 0)

config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
reset("pi", "   ")
require("agent-fleet.launch_input").interactive_pick()
check("input blank after pick: no launch", launch_calls == 0)

-- Test 9: vim.cmd("AgentPick fix auth") end-to-end
restore()
vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/agent-fleet.lua")
config.setup({
  agents = {
    pi = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
    claude = {
      cmd = "false",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
  },
  default_agent = "pi",
  start_insert = false,
})

local orig_jobstart = vim.fn.jobstart
local captured_e2e = nil
vim.fn.jobstart = function(argv, _)
  captured_e2e = vim.deepcopy(argv)
  return 1
end

vim.ui.select = function(items, opts, on_choice)
  on_choice("claude")
end

local fresh_cwd = vim.fn.tempname()
vim.fn.mkdir(fresh_cwd, "p")
vim.fn.chdir(fresh_cwd)
vim.cmd("AgentPick fix auth")
check(
  "AgentPick command: prompt appended as last argv element",
  captured_e2e ~= nil and captured_e2e[#captured_e2e] == "fix auth"
)
check(
  "AgentPick command: picked agent (claude) is used, not default (pi)",
  captured_e2e ~= nil and captured_e2e[1] == "false"
)

vim.fn.jobstart = orig_jobstart

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
