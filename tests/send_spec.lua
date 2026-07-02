vim.opt.runtimepath:append(vim.fn.getcwd())

local send = require("agent-fleet.send")
local agent = require("agent-fleet.agent")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

check(
  "file directly inside cwd, single line",
  send.build_reference("/p/main.go", "/p", 12, 12) == "main.go:12"
)
check(
  "nested file inside cwd, range",
  send.build_reference("/p/lua/x.lua", "/p", 3, 7) == "lua/x.lua:3-7"
)
check(
  "cwd given with trailing slash still works",
  send.build_reference("/p/main.go", "/p/", 5, 5) == "main.go:5"
)
check(
  "file outside cwd returns absolute path",
  send.build_reference("/etc/hosts", "/p", 1, 2) == "/etc/hosts:1-2"
)
check(
  "reversed lines are normalized",
  send.build_reference("/p/a", "/p", 9, 4) == "a:4-9"
)
check("empty path returns nil", send.build_reference("", "/p", 1, 1) == nil)
check("nil path returns nil", send.build_reference(nil, "/p", 1, 1) == nil)

local orig_agents = agent.agents
local orig_last_focused_id = agent.last_focused_id

agent.agents = {}
agent.last_focused_id = nil

local buf1 = vim.api.nvim_create_buf(false, true)
local buf2 = vim.api.nvim_create_buf(false, true)

local a1 = { id = 1, name = "one", bufnr = buf1, job = 101, cwd = "/p" }
local a2 = { id = 2, name = "two", bufnr = buf2, job = 102, cwd = "/p" }

agent.agents = { [1] = a1 }
agent.last_focused_id = nil
local resolved, candidates = send.resolve_target()
check("one live agent, no last_focused -> returns that agent", resolved == a1)
check("one live agent, no last_focused -> candidates nil", candidates == nil)

agent.agents = { [1] = a1, [2] = a2 }
agent.last_focused_id = 2
resolved, candidates = send.resolve_target()
check("two live agents, last_focused set -> returns last-focused agent", resolved == a2)
check("two live agents, last_focused set -> candidates nil", candidates == nil)

agent.agents = { [1] = a1, [2] = a2 }
agent.last_focused_id = 999
resolved, candidates = send.resolve_target()
check("last_focused not in agents -> resolved nil", resolved == nil)
check("last_focused not in agents -> candidates list of length 2", candidates ~= nil and #candidates == 2)

agent.agents = {}
agent.last_focused_id = nil
resolved, candidates = send.resolve_target()
check("no agents -> resolved nil", resolved == nil)
check("no agents -> candidates empty list", candidates ~= nil and #candidates == 0)

agent.agents = orig_agents
agent.last_focused_id = orig_last_focused_id

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
