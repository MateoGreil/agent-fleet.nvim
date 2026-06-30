vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

config.setup({ agents = { pi = {} } })
local c1 = config.get()
check("pi preset cmd", c1.agents.pi.cmd == "pi")
check("pi preset backend", c1.agents.pi.backend == "pi")
check("pi preset resume_flag", c1.agents.pi.session.resume_flag == "--session")
check("pi preset sessions_dir ends with .pi/agent/sessions", c1.agents.pi.sessions_dir:match("%.pi/agent/sessions$") ~= nil)
check("single agent becomes default", c1.default_agent == "pi")

config.setup({ agents = { claude = {} } })
local c2 = config.get()
check("claude preset cmd", c2.agents.claude.cmd == "claude")
check("claude preset backend", c2.agents.claude.backend == "claude")
check("claude preset resume_flag", c2.agents.claude.session.resume_flag == "--resume")
check("claude preset sessions_dir ends with .claude/projects", c2.agents.claude.sessions_dir:match("%.claude/projects$") ~= nil)
check("single claude becomes default", c2.default_agent == "claude")

config.setup({ agents = { aider = { cmd = "aider" } } })
local c3 = config.get()
check("generic agent cmd", c3.agents.aider.cmd == "aider")
check("generic agent backend", c3.agents.aider.backend == "generic")
check("generic agent no session", c3.agents.aider.session == nil)

config.setup({ agents = { mypi = { cmd = "pi", backend = "pi" } } })
local c4 = config.get()
check("explicit backend pi inherits preset", c4.agents.mypi.cmd == "pi")
check("explicit backend pi has session flags", c4.agents.mypi.session ~= nil and c4.agents.mypi.session.resume_flag == "--session")

config.setup({ agents = { claude = { cmd = "claude-canary" } } })
local c5 = config.get()
check("override cmd", c5.agents.claude.cmd == "claude-canary")
check("override keeps backend", c5.agents.claude.backend == "claude")

config.setup({ agents = { pi = {}, claude = {} } })
local c6 = config.get()
check("multi-agent no default_agent set", c6.default_agent == nil)

config.setup({ agents = { pi = {}, claude = {} }, default_agent = "pi" })
local c7 = config.get()
check("explicit default_agent honored", c7.default_agent == "pi")

config.setup({ agents = { pi = {}, claude = {} }, default_agent = "nonexistent" })
local c8 = config.get()
check("explicit nonexistent default_agent still set", c8.default_agent == "nonexistent")

config.setup({ agents = {} })
local c9 = config.get()
check("empty agents allowed", c9.agents ~= nil)
check("empty agents no default", c9.default_agent == nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
