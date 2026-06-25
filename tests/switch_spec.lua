vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

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

-- Case 1: no session file on disk -> nil, nothing spawned.
local r1 = agent.resume_session({ id = "nofile", cwd = "/tmp", type = "pi" })
check("case1 no session file returns nil", r1 == nil)
check("case1 no session file spawns nothing", count_agents() == 0)

-- Case 2: fake session file present (not in roster) -> resumes.
local cwd2 = vim.fn.tempname()
vim.fn.mkdir(cwd2, "p")
local id2 = "abcd1234-0000-0000-0000-000000000002"
vim.fn.mkdir(sessions_dir .. "/proj2", "p")
local sf2 = sessions_dir .. "/proj2/2026-01-01T00-00-00_" .. id2 .. ".jsonl"
local fd = io.open(sf2, "w")
fd:write("{}\n")
fd:close()

local r2 = agent.resume_session({ id = id2, cwd = cwd2, type = "pi" })
check("case2 returns agent", r2 ~= nil)
check("case2 session_id == id", r2 ~= nil and r2.session_id == id2)
check("case2 buffer is terminal", r2 ~= nil and vim.bo[r2.bufnr].buftype == "terminal")
check("case2 spawned in spec.cwd", r2 ~= nil and r2.cwd == cwd2)
check("case2 name derived for non-roster", r2 ~= nil and r2.name == "pi:" .. id2:sub(1, 8))

-- Case 3: live dedupe -> returns the same agent, no second entry.
local cwd3 = vim.fn.tempname()
vim.fn.mkdir(cwd3, "p")
local live = agent.launch({ agent = "pi", name = "live-three", cwd = cwd3 })
check("case3 live launch ok", live ~= nil)
local before = count_agents()
local r3 = agent.resume_session({ id = live.session_id, cwd = cwd3, type = "pi" })
check("case3 returns same agent", r3 == live)
check("case3 same bufnr", r3 ~= nil and live ~= nil and r3.bufnr == live.bufnr)
check("case3 no second entry", count_agents() == before)

-- Case 4: roster name preferred when entry exists.
local cwd4 = vim.fn.tempname()
vim.fn.mkdir(cwd4, "p")
local id4 = "abcd1234-0000-0000-0000-000000000004"
roster.add({ id = id4, type = "pi", name = "named-four", cwd = cwd4 })
vim.fn.mkdir(sessions_dir .. "/proj4", "p")
local sf4 = sessions_dir .. "/proj4/2026-01-01T00-00-00_" .. id4 .. ".jsonl"
local fd4 = io.open(sf4, "w")
fd4:write("{}\n")
fd4:close()
local r4 = agent.resume_session({ id = id4, cwd = cwd4, type = "pi" })
check("case4 roster name used", r4 ~= nil and r4.name == "named-four")

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
