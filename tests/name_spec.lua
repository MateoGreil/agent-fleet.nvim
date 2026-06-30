vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/agent-fleet.lua")

local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function fresh_cwd()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function setup()
  config.setup({
    agents = {
      pi = {
        cmd = "true",
        session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
      },
    },
    default_agent = "pi",
    start_insert = false,
  })
end

setup()

local orig_jobstart = vim.fn.jobstart
local captured
vim.fn.jobstart = function(argv, _)
  captured = vim.deepcopy(argv)
  return 1
end

-- :Agent <text> -> launch with the text as the initial prompt (last argv element)
captured = nil
vim.fn.chdir(fresh_cwd())
vim.cmd("Agent fix auth module")
check("args: prompt appended as last argv element", captured ~= nil and captured[#captured] == "fix auth module")

-- :Agent (no args) -> prompt via vim.ui.input, launch with the typed prompt
local orig_input = vim.ui.input
captured = nil
vim.ui.input = function(opts, on_confirm)
  check("no args: shows the New agent prompt input", opts ~= nil and opts.prompt == "New agent prompt: ")
  on_confirm("review the diff")
end
vim.fn.chdir(fresh_cwd())
vim.cmd("Agent")
check("no args: launches with the typed prompt", captured ~= nil and captured[#captured] == "review the diff")

-- :Agent (no args) with cancelled / blank input -> no launch
captured = nil
vim.ui.input = function(_, on_confirm)
  on_confirm(nil)
end
vim.fn.chdir(fresh_cwd())
vim.cmd("Agent")
check("no args: cancelled input does not launch", captured == nil)

captured = nil
vim.ui.input = function(_, on_confirm)
  on_confirm("   ")
end
vim.fn.chdir(fresh_cwd())
vim.cmd("Agent")
check("no args: blank input does not launch", captured == nil)

-- :Agent with only whitespace args -> treated as no args (input dialog)
captured = nil
local prompted = false
vim.ui.input = function(_, on_confirm)
  prompted = true
  on_confirm(nil)
end
vim.fn.chdir(fresh_cwd())
vim.cmd("Agent    ")
check("whitespace args: falls back to the input dialog", prompted == true)

vim.ui.input = orig_input
vim.fn.jobstart = orig_jobstart

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
