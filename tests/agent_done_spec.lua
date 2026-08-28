vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/agent-fleet.lua")

local actions = require("agent-fleet.actions")
local agent = require("agent-fleet.agent")
local board = require("agent-fleet.board")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local cwd = vim.fn.tempname()
vim.fn.mkdir(cwd, "p")
vim.fn.chdir(cwd)
config.setup({ agents = { opencode = { cmd = "true", sessions_dir = cwd } }, start_insert = false })

local session_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)
vim.b[bufnr].agent_fleet = { id = 1, name = "pending", agent = "opencode" }
agent.agents[1] = {
  id = 1,
  agent = "opencode",
  session_id = nil,
  cwd = cwd,
  name = "pending",
  bufnr = bufnr,
  spawned_ms = os.time() * 1000,
}
local pending_row = actions.current_live_row()
check("current live row exposes unbound session", pending_row ~= nil and pending_row.unbound == true)

local original_rows = board.rows
local original_select = vim.ui.select
local rows_calls = 0
local select_calls = 0
board.rows = function()
  rows_calls = rows_calls + 1
  vim.defer_fn(function()
    if agent.agents[1] then
      agent.agents[1].session_id = session_id
      roster.add({ id = session_id, type = "opencode", name = "pending", cwd = cwd })
    end
  end, 10)
  return {}
end
vim.ui.select = function()
  select_calls = select_calls + 1
end

vim.cmd("AgentDone")
local marked_done = vim.wait(1000, function()
  local entry = roster.get(session_id)
  return entry ~= nil and entry.done == true
end, 10)

check("AgentDone waits for OpenCode session binding", marked_done)
check("AgentDone refreshes while binding", rows_calls > 0)
check("AgentDone does not open the picker", select_calls == 0)

vim.ui.select = original_select
board.rows = original_rows
vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
