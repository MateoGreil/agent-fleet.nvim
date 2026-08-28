vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")
local actions = require("agent-fleet.actions")
local oc = require("agent-fleet.backends.opencode")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, "p")
vim.fn.writefile({ "" }, stub_dir .. "/opencode.db")

config.setup({ agents = { opencode = { cmd = "opencode", sessions_dir = stub_dir } }, start_insert = false })

local cwd_r = vim.fn.tempname()
vim.fn.mkdir(cwd_r, "p")

oc._snapshots = {}
oc._inflight = {}

roster.add({ id = "ses_res1", type = "opencode", name = "resumable", cwd = cwd_r })
oc._snapshots[cwd_r] = {
  fetched_mono = 0,
  rows = { { id = "ses_res1", cwd = cwd_r, created_at = 1, last_activity = 2, title = "resumable", state = "idle" } },
}

local captured
local orig_jobstart = vim.fn.jobstart
vim.fn.jobstart = function(argv, _)
  captured = vim.deepcopy(argv)
  return 1
end

local r1 = agent.resume("ses_res1")
check("resume spawns agent", r1 ~= nil)
check(
  "resume argv is cmd --session id",
  captured ~= nil
    and #captured == 3
    and captured[1] == "opencode"
    and captured[2] == "--session"
    and captured[3] == "ses_res1"
)
check("resume argv never contains --fork", captured ~= nil and not vim.tbl_contains(captured, "--fork"))
check("resumed agent session_id set", r1 ~= nil and r1.session_id == "ses_res1")

oc._snapshots[cwd_r].rows = {}
roster.add({ id = "ses_gone", type = "opencode", name = "gone", cwd = cwd_r })
captured = nil
local r2 = agent.resume("ses_gone")
check("warm snapshot without id refuses resume", r2 == nil and captured == nil)

oc._snapshots[cwd_r] = nil
roster.add({ id = "ses_cold", type = "opencode", name = "cold", cwd = cwd_r })
local r3 = agent.resume("ses_cold")
check("cold snapshot resumes optimistically", r3 ~= nil and r3.session_id == "ses_cold")

local keys = {}
for k in pairs(agent.agents) do
  keys[#keys + 1] = k
end
for _, k in ipairs(keys) do
  agent.agents[k] = nil
end
vim.fn.jobstart = orig_jobstart

local buf_u = vim.api.nvim_create_buf(false, true)
agent.agents["u9"] = { id = 9, agent = "opencode", session_id = nil, cwd = cwd_r, name = "unbound-nine", spawned_ms = os.time() * 1000, bufnr = buf_u }

local focused = agent.resume_session({ id = "live-9", cwd = cwd_r, type = "opencode" })
check("synthetic id focuses live terminal", focused ~= nil and focused.bufnr == buf_u)

local before = #roster.list({ cwd = cwd_r, include_archived = true })
local unbound_row = { id = "live-9", name = "unbound-nine", cwd = cwd_r, type = "opencode", live = true, bufnr = buf_u, unbound = true, done = false, archived = false }
check("actions.done on unbound row returns nil", actions.done(unbound_row) == nil)
check("actions.done on unbound row leaves roster", #roster.list({ cwd = cwd_r, include_archived = true }) == before)
check("actions.archive on unbound row returns nil", actions.archive(unbound_row) == nil)
check("roster still unchanged after archive attempt", #roster.list({ cwd = cwd_r, include_archived = true }) == before)

agent.agents["u9"] = nil
oc._snapshots = {}
oc._inflight = {}

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
