vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")
local agent = require("agent-fleet.agent")
local actions = require("agent-fleet.actions")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

-- config defaults for auto_name
config.setup({})
local an = config.get().auto_name
check("auto_name table present", type(an) == "table")
check("auto_name.enabled false", an.enabled == false)
check("auto_name.model nil", an.model == nil)
check("auto_name.thinking off", an.thinking == "off")
check("auto_name.poll_interval_ms 3000", an.poll_interval_ms == 3000)
check("auto_name.poll_timeout_ms 120000", an.poll_timeout_ms == 120000)
check("auto_name.namer_timeout_ms 30000", an.namer_timeout_ms == 30000)
check("auto_name.max_chars 2000", an.max_chars == 2000)

-- roster.set_auto_named
roster.add({ id = "auto-1", type = "pi", name = "n", cwd = "/p" })
check("roster default auto_named false", roster.get("auto-1").auto_named == false)
roster.set_auto_named("auto-1", true)
check("set_auto_named true", roster.get("auto-1").auto_named == true)
roster.set_auto_named("auto-1", false)
check("set_auto_named false", roster.get("auto-1").auto_named == false)
check("set_auto_named missing returns nil", roster.set_auto_named("nope", true) == nil)

-- launch sets auto_named
local cwd = vim.fn.tempname()
vim.fn.mkdir(cwd, "p")
config.setup({
  agents = {
    pi = {
      cmd = "true",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
  },
  start_insert = false,
})

local a = agent.launch({ agent = "pi", cwd = cwd })
check("launch without name returned agent", a ~= nil)
check("live agent auto_named true without name", a ~= nil and a.auto_named == true)
check("roster auto_named true without name", a ~= nil and roster.get(a.session_id).auto_named == true)

local b = agent.launch({ agent = "pi", name = "x", cwd = cwd })
check("launch with name returned agent", b ~= nil)
check("live agent auto_named false with name", b ~= nil and b.auto_named == false)
check("roster auto_named false with name", b ~= nil and roster.get(b.session_id).auto_named == false)

-- actions.rename manual clears auto_named (dead row)
local id_m = "mmmmmmmm-mmmm-mmmm-mmmm-mmmmmmmmmm01"
roster.add({ id = id_m, type = "pi", name = "old", cwd = "/p", auto_named = true })
actions.rename({ id = id_m, name = "old", cwd = "/p", live = false }, "new")
check("manual rename sets name", roster.get(id_m).name == "new")
check("manual rename clears auto_named", roster.get(id_m).auto_named == false)

-- actions.rename auto preserves auto_named (dead row)
local id_a = "mmmmmmmm-mmmm-mmmm-mmmm-mmmmmmmmmm02"
roster.add({ id = id_a, type = "pi", name = "old", cwd = "/p", auto_named = true })
actions.rename({ id = id_a, name = "old", cwd = "/p", live = false }, "new", { auto = true })
check("auto rename sets name", roster.get(id_a).name == "new")
check("auto rename preserves auto_named", roster.get(id_a).auto_named == true)

-- actions.rename manual on live row clears live agent flag
local id_l = "mmmmmmmm-mmmm-mmmm-mmmm-mmmmmmmmmm03"
local buf_l = vim.api.nvim_create_buf(false, true)
agent.agents[91] = { session_id = id_l, bufnr = buf_l, cwd = "/p", name = "old", auto_named = true }
vim.b[buf_l].agent_fleet = { id = 91 }
roster.add({ id = id_l, type = "pi", name = "old", cwd = "/p", auto_named = true })
actions.rename({ id = id_l, name = "old", cwd = "/p", live = true, bufnr = buf_l }, "newlive")
check("live manual rename sets roster name", roster.get(id_l).name == "newlive")
check("live manual rename clears roster auto_named", roster.get(id_l).auto_named == false)
check("live manual rename clears live agent auto_named", agent.agents[91].auto_named == false)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
