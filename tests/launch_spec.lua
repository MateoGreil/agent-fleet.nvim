vim.opt.runtimepath:append(vim.fn.getcwd())

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

config.setup({
  agents = {
    pi = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
  },
  start_insert = false,
})

local orig_jobstart = vim.fn.jobstart
local captured
vim.fn.jobstart = function(argv, _)
  captured = vim.deepcopy(argv)
  return 1
end

agent.launch({ agent = "pi", name = "prompt-pi", cwd = cwd_pi, prompt = "hello world" })
check("prompt appended as last argv element", captured ~= nil and captured[#captured] == "hello world")
check(
  "session flags precede the prompt",
  captured ~= nil
    and captured[#captured - 1] == "prompt-pi"
    and captured[#captured - 4] == "--session-id"
)

captured = nil
agent.launch({ agent = "pi", name = "noprompt-pi", cwd = cwd_pi })
check("no prompt -> last argv element is the name", captured ~= nil and captured[#captured] == "noprompt-pi")

captured = nil
agent.launch({ agent = "pi", name = "empty-pi", cwd = cwd_pi, prompt = "   " })
check("blank prompt is not appended", captured ~= nil and captured[#captured] == "empty-pi")

vim.fn.jobstart = orig_jobstart

config.setup({
  agents = {
    claude = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--resume" },
    },
  },
  start_insert = false,
})

local b = agent.launch({ agent = "claude", name = "test-claude", cwd = cwd_claude })
check("claude launch returned agent", b ~= nil)
check("claude session_id is valid uuid", b ~= nil and type(b.session_id) == "string" and b.session_id:match(uuid_pat) ~= nil)

local claude_entries = roster.list({ include_archived = true })
local found_claude = false
for _, entry in ipairs(claude_entries) do
  if entry.id == b.session_id then
    check("claude roster type == claude", entry.type == "claude")
    found_claude = true
    break
  end
end
check("found claude roster entry", found_claude)

local before = #roster.list({ include_archived = true })
config.setup({ agents = { plain = { cmd = "true" } }, start_insert = false })
local c = agent.launch({ agent = "plain", name = "test-plain", cwd = cwd_claude })
check("plain launch returned agent", c ~= nil)
check("plain session_id is nil", c ~= nil and c.session_id == nil)
check("no roster entry written for no-session agent", #roster.list({ include_archived = true }) == before)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
