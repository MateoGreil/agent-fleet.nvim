vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")
local agent = require("agent-fleet.agent")
local actions = require("agent-fleet.actions")
local autoname = require("agent-fleet.autoname")

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
check("auto_name.poll_interval_ms removed", an.poll_interval_ms == nil)
check("auto_name.poll_timeout_ms removed", an.poll_timeout_ms == nil)
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

-- autoname pure helpers

check("system_prompt is string", type(autoname.system_prompt) == "string" and #autoname.system_prompt > 0)

check("first_user_text removed", autoname.first_user_text == nil)
check("locate_file removed", autoname.locate_file == nil)

check("sanitize plain", autoname.sanitize("fix auth bug", 5, 100) == "fix auth bug")
check("sanitize double quotes", autoname.sanitize('"fix auth"', 5, 100) == "fix auth")
check("sanitize single quotes", autoname.sanitize("'fix auth'", 5, 100) == "fix auth")
check("sanitize backticks", autoname.sanitize("`dark mode`", 5, 100) == "dark mode")
check("sanitize first line", autoname.sanitize("fix auth\nsome explanation here", 5, 100) == "fix auth")
check(
  "sanitize word cap",
  autoname.sanitize("one two three four five six seven", 5, 100) == "one two three four five"
)
local long_name = string.rep("a", 150)
local s_long = autoname.sanitize(long_name, 5, 100)
check("sanitize char cap", s_long ~= nil and #s_long <= 100)
check("sanitize whitespace only", autoname.sanitize("   ", 5, 100) == nil)
check("sanitize nil", autoname.sanitize(nil, 5, 100) == nil)

local function idx_of(list, val)
  for i, v in ipairs(list) do
    if v == val then
      return i
    end
  end
  return nil
end

local function flag_followed_by(list, flag, value)
  local i = idx_of(list, flag)
  return i ~= nil and list[i + 1] == value
end

local argv = autoname.build_argv("pi", "PROMPT", "SYS", "MODEL", "off")
check("build_argv first element pi", argv[1] == "pi")
check("build_argv -p PROMPT", flag_followed_by(argv, "-p", "PROMPT"))
check("build_argv --system-prompt SYS", flag_followed_by(argv, "--system-prompt", "SYS"))
check("build_argv --model MODEL", flag_followed_by(argv, "--model", "MODEL"))
check("build_argv --thinking off", flag_followed_by(argv, "--thinking", "off"))
check("build_argv has --no-tools", idx_of(argv, "--no-tools") ~= nil)
check("build_argv has --no-session", idx_of(argv, "--no-session") ~= nil)
check("build_argv has --no-context-files", idx_of(argv, "--no-context-files") ~= nil)
check("build_argv --mode text", flag_followed_by(argv, "--mode", "text"))

local argv2 = autoname.build_argv("pi --foo", "P", "S", "M", "off")
check("build_argv split base cmd 1", argv2[1] == "pi")
check("build_argv split base cmd 2", argv2[2] == "--foo")

-- autoname.eligible matrix
local elig_agent = { auto_named = true, session_id = "elig-sid", agent = "pi" }
local elig_cfg = { auto_name = { enabled = true, model = "fake/model" } }
check("eligible all true", autoname.eligible(elig_agent, elig_cfg) == true)
check(
  "eligible disabled",
  autoname.eligible(elig_agent, { auto_name = { enabled = false, model = "fake/model" } }) == false
)
check(
  "eligible auto_named false",
  autoname.eligible({ auto_named = false, session_id = "elig-sid", agent = "pi" }, elig_cfg) == false
)
check(
  "eligible non-pi agent",
  autoname.eligible({ auto_named = true, session_id = "elig-sid", agent = "claude" }, elig_cfg) == false
)
check(
  "eligible nil session_id",
  autoname.eligible({ auto_named = true, session_id = nil, agent = "pi" }, elig_cfg) == false
)
check("eligible nil model", autoname.eligible(elig_agent, { auto_name = { enabled = true } }) == false)

-- autoname.apply_name happy path
local id_ap = "apply-happy-00000001"
local cwd_ap = "/apply/cwd"
roster.add({ id = id_ap, type = "pi", name = "pi-1", cwd = cwd_ap, auto_named = true })
local buf_ap = vim.api.nvim_create_buf(false, true)
agent.agents[701] = { session_id = id_ap, bufnr = buf_ap, cwd = cwd_ap, name = "pi-1", auto_named = true, agent = "pi" }
autoname.apply_name(id_ap, "Fix Login Flow")
check("apply_name sets roster name", roster.get(id_ap).name == "Fix Login Flow")
check("apply_name preserves auto_named", roster.get(id_ap).auto_named == true)
check("apply_name updates live agent name", agent.agents[701].name == "Fix Login Flow")
agent.agents[701] = nil

-- autoname.apply_name junk -> no-op
local id_junk = "apply-junk-00000001"
roster.add({ id = id_junk, type = "pi", name = "keepme", cwd = cwd_ap, auto_named = true })
autoname.apply_name(id_junk, "   ")
check("apply_name junk no-op", roster.get(id_junk).name == "keepme")

-- autoname.apply_name when user already renamed -> gate blocks
local id_ren = "apply-renamed-00000001"
roster.add({ id = id_ren, type = "pi", name = "keepme2", cwd = cwd_ap, auto_named = true })
roster.set_auto_named(id_ren, false)
autoname.apply_name(id_ren, "Some Name")
check("apply_name already-renamed no-op", roster.get(id_ren).name == "keepme2")

-- autoname.name_from_prompt end-to-end with injected runner
config.setup({
  auto_name = {
    enabled = true,
    model = "fake/model",
    namer_timeout_ms = 1000,
    max_chars = 2000,
    thinking = "off",
  },
  agents = {
    pi = { cmd = "true", session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" } },
  },
  start_insert = false,
})
local id_arm = "arm-e2e-00000001"
local cwd_arm = "/home/test/proj"
roster.add({ id = id_arm, type = "pi", name = "pi-9", cwd = cwd_arm, auto_named = true })
local buf_arm = vim.api.nvim_create_buf(false, true)
agent.agents[801] =
  { session_id = id_arm, bufnr = buf_arm, cwd = cwd_arm, name = "pi-9", auto_named = true, agent = "pi" }
local saved_runner = autoname.runner
local seen_prompt
autoname.runner = function(argv, _cwd, _timeout, cb)
  for i, v in ipairs(argv) do
    if v == "-p" then
      seen_prompt = argv[i + 1]
    end
  end
  cb("Billing Export")
end
autoname.name_from_prompt(
  { session_id = id_arm, cwd = cwd_arm, agent = "pi", auto_named = true },
  "add billing export"
)
vim.wait(800, function()
  return roster.get(id_arm).name == "Billing Export"
end)
autoname.runner = saved_runner
check("name_from_prompt e2e renamed", roster.get(id_arm).name == "Billing Export")
check("name_from_prompt e2e preserves auto_named", roster.get(id_arm).auto_named == true)
check("name_from_prompt passes prompt to namer", seen_prompt == "add billing export")
agent.agents[801] = nil

-- name_from_prompt without a prompt -> runner never called (keeps numbered name)
local no_prompt_called = false
local saved_runner_np = autoname.runner
autoname.runner = function()
  no_prompt_called = true
end
local id_np = "arm-noprompt-00000001"
roster.add({ id = id_np, type = "pi", name = "pi-7", cwd = "/p", auto_named = true })
agent.agents[803] =
  { session_id = id_np, bufnr = vim.api.nvim_create_buf(false, true), cwd = "/p", name = "pi-7", auto_named = true, agent = "pi" }
autoname.name_from_prompt({ session_id = id_np, cwd = "/p", agent = "pi", auto_named = true }, nil)
autoname.name_from_prompt({ session_id = id_np, cwd = "/p", agent = "pi", auto_named = true }, "   ")
vim.wait(50)
autoname.runner = saved_runner_np
check("name_from_prompt no prompt runner not called", no_prompt_called == false)
check("name_from_prompt no prompt keeps name", roster.get(id_np).name == "pi-7")
agent.agents[803] = nil

-- name_from_prompt disabled -> runner never called
config.setup({
  auto_name = { enabled = false },
  agents = {
    pi = { cmd = "true", session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" } },
  },
  start_insert = false,
})
local disabled_called = false
local saved_runner2 = autoname.runner
autoname.runner = function()
  disabled_called = true
end
local id_dis = "arm-disabled-00000001"
roster.add({ id = id_dis, type = "pi", name = "pi-d", cwd = "/p", auto_named = true })
agent.agents[802] =
  { session_id = id_dis, bufnr = vim.api.nvim_create_buf(false, true), cwd = "/p", name = "pi-d", auto_named = true, agent = "pi" }
autoname.name_from_prompt({ session_id = id_dis, cwd = "/p", agent = "pi", auto_named = true }, "do a thing")
vim.wait(50)
autoname.runner = saved_runner2
check("disabled runner not called", disabled_called == false)
check("disabled no rename", roster.get(id_dis).name == "pi-d")
agent.agents[802] = nil

-- default_name pure helper
check("default_name plain", autoname.default_name("fix the login flow") == "fix the login flow")
check("default_name nil prompt", autoname.default_name(nil) == nil)
check("default_name empty prompt", autoname.default_name("   ") == nil)
check("default_name first line only", autoname.default_name("do a thing\nmore detail here") == "do a thing")
check("default_name collapses whitespace", autoname.default_name("a    b\tc") == "a b c")
local dn_long = autoname.default_name(string.rep("x", 80))
check("default_name truncates with ellipsis", dn_long == string.rep("x", 39) .. "\u{2026}")
check("default_name truncated length", vim.fn.strchars(dn_long) == 40)
check(
  "default_name char-aware truncation keeps utf8 intact",
  not autoname.default_name(string.rep("é", 80)):find("\xef\xbf\xbd")
)

-- launch derives the default name from the initial prompt (replaces pi-N)
local cwd_dn = vim.fn.tempname()
vim.fn.mkdir(cwd_dn, "p")
config.setup({
  agents = {
    pi = { cmd = "true", session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" } },
  },
  start_insert = false,
})
local a_dn = agent.launch({ agent = "pi", cwd = cwd_dn, prompt = "add dark mode toggle" })
check("launch with prompt names from prompt", a_dn ~= nil and a_dn.name == "add dark mode toggle")
check("launch with prompt stays auto_named", a_dn ~= nil and a_dn.auto_named == true)
check("launch with prompt roster name", a_dn ~= nil and roster.get(a_dn.session_id).name == "add dark mode toggle")
local a_noprompt = agent.launch({ agent = "pi", cwd = cwd_dn })
check("launch without prompt falls back to kind-N", a_noprompt ~= nil and a_noprompt.name:match("^pi%-%d+$") ~= nil)
local a_named = agent.launch({ agent = "pi", cwd = cwd_dn, name = "explicit", prompt = "ignored prompt" })
check("explicit name beats prompt", a_named ~= nil and a_named.name == "explicit")

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
