vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")
vim.cmd("source /home/mat/agent-fleet.nvim/plugin/agent-fleet.lua")

local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

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

local function entries_for(cwd)
  local matches = {}
  for _, e in ipairs(roster.list({ include_archived = true })) do
    if e.cwd == cwd then
      matches[#matches + 1] = e
    end
  end
  return matches
end

setup()

local cwd_named = fresh_cwd()
vim.fn.chdir(cwd_named)
vim.cmd("Agent fix auth module")
local named = entries_for(cwd_named)
check("named: exactly one entry", #named == 1)
check("named: name is verbatim", named[1] ~= nil and named[1].name == "fix auth module")

local cwd_default = fresh_cwd()
vim.fn.chdir(cwd_default)
vim.cmd("Agent")
local default = entries_for(cwd_default)
check("default: exactly one entry", #default == 1)
check("default: name matches <kind>-<seq>", default[1] ~= nil and default[1].name:match("^pi%-%d+$") ~= nil)

local cwd_ws = fresh_cwd()
vim.fn.chdir(cwd_ws)
vim.cmd("Agent    ")
local ws = entries_for(cwd_ws)
check("whitespace: exactly one entry", #ws == 1)
check("whitespace: name falls back to default", ws[1] ~= nil and ws[1].name:match("^pi%-%d+$") ~= nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
