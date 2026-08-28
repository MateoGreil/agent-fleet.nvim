vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")
local board = require("agent-fleet.board")
local agent = require("agent-fleet.agent")
local roster = require("agent-fleet.roster")
local oc = require("agent-fleet.backends.opencode")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function find_row(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id then
      return row
    end
  end
  return nil
end

local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, "p")
local stub = stub_dir .. "/opencode-norefresh"
vim.fn.writefile({ "#!/usr/bin/env bash", "exit 0" }, stub)
vim.fn.setfperm(stub, "rwxr-xr-x")

config.setup({ agents = { opencode = { cmd = stub, sessions_dir = stub_dir } }, start_insert = false })
local W = "/w-board"
local T = os.time() * 1000

local buf = vim.api.nvim_create_buf(false, true)
agent.agents["u1"] = {
  id = 41,
  agent = "opencode",
  session_id = nil,
  cwd = W,
  name = "unbound-one",
  spawned_ms = T - 60000,
  bufnr = buf,
}

local rows = board.rows({ cwd = W, include_archived = true })
local r = find_row(rows, "live-41")
check("unbound live agent appears with synthetic id", r ~= nil)
check("unbound row live + unbound flags", r ~= nil and r.live == true and r.unbound == true)
check("unbound row state new", r ~= nil and r.state == "new")
check("unbound row type opencode", r ~= nil and r.type == "opencode")
check("unbound row name", r ~= nil and r.name == "unbound-one")
check("unbound row last_activity from spawn", r ~= nil and r.last_activity == T - 60000)

oc._snapshots[W] = {
  fetched_mono = 0,
  rows = {
    { id = "ses_titled", cwd = W, created_at = 1000, last_activity = 2000, title = "Fix login", state = "idle" },
    { id = "ses_def_titled", cwd = W, created_at = 3000, last_activity = 4000, title = "New session - 2026-08-26T10:00:00.000Z", state = "working" },
  },
}
local rows2 = board.rows({ cwd = W })
local r_titled = find_row(rows2, "ses_titled")
check("disk-discovered session appears", r_titled ~= nil)
check("disk row uses title as name", r_titled ~= nil and r_titled.name == "Fix login")
check("disk row state from snapshot", r_titled ~= nil and r_titled.state == "idle")
check("disk row last_activity from snapshot", r_titled ~= nil and r_titled.last_activity == 2000)
check("disk row type opencode", r_titled ~= nil and r_titled.type == "opencode")

local r_def = find_row(rows2, "ses_def_titled")
check("default title falls back to id name", r_def ~= nil and r_def.name == "opencode:ses_def_")
check("default-titled row state working", r_def ~= nil and r_def.state == "working")

roster.add({ id = "ses_bound", type = "opencode", name = "bound-one", cwd = W })
agent.agents["u1"].session_id = "ses_bound"
local rows3 = board.rows({ cwd = W, include_archived = true })
check("bound agent no longer has synthetic row", find_row(rows3, "live-41") == nil)
local r_bound = find_row(rows3, "ses_bound")
check("bound agent row appears under real id", r_bound ~= nil and r_bound.live == true and r_bound.unbound == nil)

agent.agents["u1"] = nil

oc._snapshots = {}
oc._inflight = {}

local e2e_dir = vim.fn.tempname()
vim.fn.mkdir(e2e_dir, "p")
local e2e_stub = e2e_dir .. "/opencode"
local e2e_fixture = e2e_dir .. "/fixture.json"
local e2e_cwd = vim.fn.tempname()
vim.fn.mkdir(e2e_cwd, "p")
vim.fn.writefile({ "#!/usr/bin/env bash", 'cat "' .. e2e_fixture .. '"' }, e2e_stub)
vim.fn.setfperm(e2e_stub, "rwxr-xr-x")

config.setup({ agents = { opencode = { cmd = e2e_stub, sessions_dir = e2e_dir } }, start_insert = false })
oc._snapshots = {}
oc._inflight = {}

local e2e_spawn_ms = os.time() * 1000
local e2e_buf = vim.api.nvim_create_buf(false, true)
agent.agents["e2e"] = { id = 77, agent = "opencode", session_id = nil, cwd = e2e_cwd, name = "e2e-agent", spawned_ms = e2e_spawn_ms, bufnr = e2e_buf }

vim.fn.writefile({ vim.json.encode({
  {
    id = "ses_e2e",
    title = "E2E session",
    directory = e2e_cwd,
    time_created = e2e_spawn_ms + 1500,
    time_updated = e2e_spawn_ms + 2000,
    last_message = '{"role":"assistant"}',
    last_part = '{"type":"tool","state":{"status":"running"}}',
  },
}) }, e2e_fixture)

local rows_e2e = board.rows({ cwd = e2e_cwd })
check("e2e unbound row visible before snapshot lands", find_row(rows_e2e, "live-77") ~= nil)
vim.wait(5000, function()
  return agent.agents["e2e"] ~= nil and agent.agents["e2e"].session_id == "ses_e2e"
end)
local rows_e2e2 = board.rows({ cwd = e2e_cwd })
local r_e2e = find_row(rows_e2e2, "ses_e2e")
check("e2e row appears under real id after binding", r_e2e ~= nil and r_e2e.live == true)
check("e2e synthetic row gone", find_row(rows_e2e2, "live-77") == nil)
check("e2e state working from running tool", r_e2e ~= nil and r_e2e.state == "working")

agent.agents["e2e"] = nil
oc._snapshots = {}
oc._inflight = {}

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
