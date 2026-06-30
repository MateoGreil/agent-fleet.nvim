vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

config.setup({
  agents = {
    gen = {
      cmd = "true",
      session = { id_flag = "--sid", name_flag = "--name", resume_flag = "--resume" },
    },
  },
  start_insert = false,
})

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local id = "deadbeef-dead-4eef-dead-beefdeadbeef"
roster.add({ id = id, type = "gen", name = "x", cwd = tmp })

local orig_jobstart = vim.fn.jobstart
local captured_argv = nil
vim.fn.jobstart = function(argv, _)
  captured_argv = vim.deepcopy(argv)
  return 1
end

local r = agent.resume(id)
check("generic resume spawned", r ~= nil)
check("captured argv has cmd", captured_argv ~= nil and captured_argv[1] == "true")
check("captured argv has resume flag", captured_argv ~= nil and vim.tbl_contains(captured_argv, "--resume"))
check("captured argv has id", captured_argv ~= nil and vim.tbl_contains(captured_argv, id))

vim.fn.jobstart = orig_jobstart

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
