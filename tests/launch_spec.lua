vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local util = require("agent-fleet.util")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local uuid_pat = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local id = util.uuid()
check("uuid is string matching v4 pattern", type(id) == "string" and id:match(uuid_pat) ~= nil)

local function deepeq(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

check("build_argv with extra", deepeq(agent.build_argv("pi", { "--session-id", "u" }), { "pi", "--session-id", "u" }))
check("build_argv empty extra", deepeq(agent.build_argv("pi", {}), { "pi" }))

local cwd_pi = vim.fn.tempname()
vim.fn.mkdir(cwd_pi, "p")
local cwd_claude = vim.fn.tempname()
vim.fn.mkdir(cwd_claude, "p")

config.setup({
  agents = {
    pi = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
  },
  start_insert = false,
})

local a = agent.launch({ agent = "pi", name = "test-pi", cwd = cwd_pi })
check("launch returned agent", a ~= nil)
check("session_id is valid uuid", a ~= nil and type(a.session_id) == "string" and a.session_id:match(uuid_pat) ~= nil)

local entries = roster.list({ include_archived = true })
check("exactly one roster entry", #entries == 1)
local e = entries[1]
check("roster id == session_id", e ~= nil and a ~= nil and e.id == a.session_id)
check("roster type == pi", e ~= nil and e.type == "pi")
check("roster name matches", e ~= nil and e.name == "test-pi")
check("roster cwd matches", e ~= nil and e.cwd == cwd_pi)

local before = #roster.list({ include_archived = true })
config.setup({ agents = { claude = { cmd = "true" } }, start_insert = false })
local c = agent.launch({ agent = "claude", name = "test-claude", cwd = cwd_claude })
check("claude launch returned agent", c ~= nil)
check("claude session_id is nil", c ~= nil and c.session_id == nil)
check("no roster entry written for no-session agent", #roster.list({ include_archived = true }) == before)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
