vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function count_agents()
  local n = 0
  for _ in pairs(agent.agents) do
    n = n + 1
  end
  return n
end

local sessions_dir = vim.fn.tempname()
vim.fn.mkdir(sessions_dir, "p")
local cwd_z = vim.fn.tempname()
vim.fn.mkdir(cwd_z, "p")
local cwd_live = vim.fn.tempname()
vim.fn.mkdir(cwd_live, "p")

config.setup({
  sessions_dir = sessions_dir,
  agents = {
    pi = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
  },
  start_insert = false,
})

local r1 = agent.resume("does-not-exist")
check("resume unknown returns nil", r1 == nil)
check("resume unknown spawns nothing", count_agents() == 0)

roster.add({ id = "zzz", type = "pi", name = "zedz", cwd = cwd_z })
local r2 = agent.resume("zzz")
check("resume with no session file returns nil", r2 == nil)
check("resume with no session file spawns nothing", count_agents() == 0)

vim.fn.mkdir(sessions_dir .. "/proj", "p")
local sf = sessions_dir .. "/proj/2026-01-01T00-00-00_zzz.jsonl"
local fd = io.open(sf, "w")
fd:write("{}\n")
fd:close()

local r3 = agent.resume("zzz")
check("resume with session file returns agent", r3 ~= nil)
check("resumed agent session_id == zzz", r3 ~= nil and r3.session_id == "zzz")
check("resumed buffer is terminal", r3 ~= nil and vim.bo[r3.bufnr].buftype == "terminal")
check("resumed agent in M.agents", (function()
  for _, x in pairs(agent.agents) do
    if x == r3 then
      return true
    end
  end
  return false
end)())
check("resume used stored entry.cwd", r3 ~= nil and r3.cwd == cwd_z)

local live = agent.launch({ agent = "pi", name = "live-one", cwd = cwd_live })
check("live launch ok", live ~= nil)
local before = count_agents()
local r4 = agent.resume(live.session_id)
check("resume live returns same agent", r4 == live)
check("resume live same bufnr", r4 ~= nil and live ~= nil and r4.bufnr == live.bufnr)
check("resume live adds no second agent", count_agents() == before)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
