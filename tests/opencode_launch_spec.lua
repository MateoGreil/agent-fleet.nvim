vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

config.setup({ agents = { opencode = { cmd = "opencode" } }, start_insert = false })

local captured
local orig_jobstart = vim.fn.jobstart
vim.fn.jobstart = function(argv, _)
  captured = vim.deepcopy(argv)
  return 1
end

local a = agent.launch({ agent = "opencode", name = "oc-one", cwd = tmp, prompt = "fix auth" })
check("launch returned agent", a ~= nil)
check(
  "argv is cmd + --prompt + prompt",
  captured ~= nil and #captured == 3 and captured[1] == "opencode" and captured[2] == "--prompt" and captured[3] == "fix auth"
)
check("session_id is nil (not pre-assigned)", a ~= nil and a.session_id == nil)
check("spawned_ms recorded as epoch ms", a ~= nil and type(a.spawned_ms) == "number" and a.spawned_ms > 1700000000000)
check("no roster entry after launch", #roster.list({ include_archived = true }) == 0)

captured = nil
agent.launch({ agent = "opencode", name = "oc-bare", cwd = tmp })
check("bare launch argv is just the cmd", captured ~= nil and #captured == 1 and captured[1] == "opencode")

captured = nil
agent.launch({ agent = "opencode", name = "oc-blank", cwd = tmp, prompt = "   " })
check("blank prompt omits --prompt", captured ~= nil and #captured == 1)

local named = nil
captured = nil
named = agent.launch({ agent = "opencode", cwd = tmp, prompt = "write the login flow end to end" })
check("default name from prompt first line", named ~= nil and named.name == "write the login flow end to end")

vim.fn.jobstart = orig_jobstart

local keys = {}
for k in pairs(agent.agents) do
  keys[#keys + 1] = k
end
for _, k in ipairs(keys) do
  agent.agents[k] = nil
end

local oc = require("agent-fleet.backends.opencode")

local stub_dir2 = vim.fn.tempname()
vim.fn.mkdir(stub_dir2, "p")
local stub2 = stub_dir2 .. "/opencode"
local fixture2 = stub_dir2 .. "/fixture.json"
vim.fn.writefile({
  "#!/usr/bin/env bash",
  'cat "' .. fixture2 .. '"',
}, stub2)
vim.fn.setfperm(stub2, "rwxr-xr-x")

local W2 = vim.fn.tempname()
vim.fn.mkdir(W2, "p")
config.setup({ agents = { opencode = { cmd = stub2, sessions_dir = stub_dir2 } }, start_insert = false })

local function snap_row(id, created, updated, last_message, last_part)
  return {
    id = id,
    title = "t-" .. id,
    directory = W2,
    time_created = created,
    time_updated = updated,
    last_message = last_message or '{"role":"assistant"}',
    last_part = last_part or '{"type":"step-finish","reason":"stop"}',
  }
end

local keys = {}
for k in pairs(agent.agents) do
  keys[#keys + 1] = k
end
for _, k in ipairs(keys) do
  agent.agents[k] = nil
end
roster.add({ id = "ses_claimed", type = "opencode", name = "ext", cwd = W2 })

local T = os.time() * 1000
agent.agents["b1"] = { id = 91, agent = "opencode", session_id = nil, cwd = W2, name = "older", spawned_ms = T - 1000, bufnr = vim.api.nvim_create_buf(false, true) }
agent.agents["b2"] = { id = 92, agent = "opencode", session_id = nil, cwd = W2, name = "newer", spawned_ms = T + 500, bufnr = vim.api.nvim_create_buf(false, true) }

vim.fn.writefile({ vim.json.encode({
  snap_row("ses_claimed", T - 60000, T - 59000),
  snap_row("ses_old", T - 200, T - 100),
  snap_row("ses_new", T + 1000, T + 2000),
}) }, fixture2)

oc._snapshots = {}
oc._inflight = {}
oc.refresh(W2, config.get().agents.opencode)
local bound = vim.wait(5000, function()
  return agent.agents["b1"].session_id ~= nil and agent.agents["b2"].session_id ~= nil
end)
check("binding pass bound both agents", bound)
check("oldest agent bound to oldest free session", agent.agents["b1"].session_id == "ses_old")
check("newest agent bound to newest session", agent.agents["b2"].session_id == "ses_new")

local entry_old = roster.get("ses_old")
check("roster entry created for ses_old", entry_old ~= nil and entry_old.type == "opencode" and entry_old.name == "older" and entry_old.cwd == W2)

local agent_ids = {}
for k in pairs(agent.agents) do
  agent_ids[#agent_ids + 1] = k
end
for _, k in ipairs(agent_ids) do
  agent.agents[k] = nil
end
roster.add({ id = "ses_far", type = "opencode", name = "far", cwd = W2 })
vim.fn.writefile({ vim.json.encode({ snap_row("ses_far", T - 60000, T - 59000) }) }, fixture2)
oc._snapshots[W2] = nil
oc._inflight[W2] = nil
agent.agents["b3"] = { id = 93, agent = "opencode", session_id = nil, cwd = W2, name = "late", spawned_ms = T + 10000, bufnr = vim.api.nvim_create_buf(false, true) }
oc.refresh(W2, config.get().agents.opencode)
vim.wait(5000, function()
  return oc._snapshots[W2] ~= nil
end)
check("session older than agent spawn stays unbound", agent.agents["b3"].session_id == nil)

oc._snapshots = {}
oc._inflight = {}
local agent_ids2 = {}
for k in pairs(agent.agents) do
  agent_ids2[#agent_ids2 + 1] = k
end
for _, k in ipairs(agent_ids2) do
  agent.agents[k] = nil
end

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
