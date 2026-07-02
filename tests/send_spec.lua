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

local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_delete(buf3, { force = true })
local a3 = { id = 3, name = "three", bufnr = buf3, job = 103, cwd = "/p" }

agent.agents = { [1] = a1, [2] = a2, [3] = a3 }
agent.last_focused_id = 3
resolved, candidates = send.resolve_target()
check("last_focused points at invalid buffer -> resolved nil", resolved == nil)
check(
  "last_focused points at invalid buffer -> candidates is live-only list of length 2",
  candidates ~= nil and #candidates == 2
)

agent.agents = orig_agents
agent.last_focused_id = orig_last_focused_id

do
  local config = require("agent-fleet.config")
  local saved_agents = agent.agents
  local saved_last_focused_id = agent.last_focused_id
  local saved_seq = agent._seq

  agent.agents = {}
  agent.last_focused_id = nil

  local cwd = vim.fn.tempname()
  vim.fn.mkdir(cwd, "p")

  config.setup({
    agents = {
      pi = { cmd = "true", session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" } },
    },
    start_insert = false,
  })

  local first = agent.launch({ agent = "pi", name = "spawn-focus-1", cwd = cwd })
  local second = agent.launch({ agent = "pi", name = "spawn-focus-2", cwd = cwd })

  check("spawn: launch returned first agent", first ~= nil)
  check("spawn: launch returned second agent", second ~= nil)
  check(
    "spawn: last_focused_id is the second launched agent's id",
    second ~= nil and agent.last_focused_id == second.id
  )

  agent.agents = saved_agents
  agent.last_focused_id = saved_last_focused_id
  agent._seq = saved_seq
end

do
  local saved_agents = agent.agents
  local saved_last_focused_id = agent.last_focused_id
  local orig_chansend = vim.fn.chansend
  local captured

  vim.fn.chansend = function(job, data)
    captured = { job = job, data = data }
    return 1
  end

  local cwd = vim.fn.tempname()
  vim.fn.mkdir(cwd, "p")
  local file = cwd .. "/main.lua"
  vim.fn.writefile({ "a", "b", "c", "d", "e" }, file)

  local orig_buf = vim.api.nvim_get_current_buf()
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local agent_buf = vim.api.nvim_create_buf(false, true)
  local sink = { id = 10, name = "sink", bufnr = agent_buf, job = 555, cwd = cwd }

  agent.agents = { [10] = sink }
  agent.last_focused_id = 10

  captured = nil
  send.from_range(2, 4)
  check("happy path: chansend called once", captured ~= nil)
  check("happy path: job matches agent job", captured ~= nil and captured.job == 555)
  check(
    "happy path: data is relpath:2-4 with trailing space, no newline",
    captured ~= nil and captured.data == "main.lua:2-4 "
  )

  captured = nil
  send.from_range(3, 3)
  check(
    "single line: data ends with :3 (no hyphen), trailing space",
    captured ~= nil and captured.data == "main.lua:3 "
  )

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(scratch)
  captured = nil
  send.from_range(1, 1)
  check("no-file buffer: chansend not called", captured == nil)

  vim.cmd("edit " .. vim.fn.fnameescape(file))
  agent.agents = {}
  agent.last_focused_id = nil
  captured = nil
  send.from_range(1, 1)
  check("no live agent: chansend not called", captured == nil)

  vim.fn.chansend = orig_chansend
  agent.agents = saved_agents
  agent.last_focused_id = saved_last_focused_id
  if vim.api.nvim_buf_is_valid(orig_buf) then
    vim.api.nvim_set_current_buf(orig_buf)
  end
end

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
