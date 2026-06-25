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

-- autoname pure helpers

local function write_jsonl(lines)
  local path = vim.fn.tempname()
  vim.fn.writefile(lines, path)
  return path
end

local function header_line()
  return vim.json.encode({ type = "session", version = 3, id = "x", cwd = "/p" })
end

local function user_msg(content)
  return vim.json.encode({ type = "message", message = { role = "user", content = content } })
end

local function assistant_msg(content)
  return vim.json.encode({ type = "message", message = { role = "assistant", content = content } })
end

check("system_prompt is string", type(autoname.system_prompt) == "string" and #autoname.system_prompt > 0)

local f_list = write_jsonl({ header_line(), user_msg({ { type = "text", text = "fix the login bug" } }) })
check("first_user_text list content", autoname.first_user_text(f_list, 2000) == "fix the login bug")

local f_multi = write_jsonl({
  header_line(),
  user_msg({ { type = "text", text = "add" }, { type = "text", text = "dark mode" } }),
})
check("first_user_text multiple text blocks", autoname.first_user_text(f_multi, 2000) == "add dark mode")

local f_str = write_jsonl({ header_line(), user_msg("refactor auth") })
check("first_user_text string content", autoname.first_user_text(f_str, 2000) == "refactor auth")

local f_first = write_jsonl({
  header_line(),
  assistant_msg({ { type = "text", text = "i am the assistant" } }),
  user_msg({ { type = "text", text = "first user message" } }),
  user_msg({ { type = "text", text = "second user message" } }),
})
check("first_user_text picks first user", autoname.first_user_text(f_first, 2000) == "first user message")

local long = "this is a very long user message that goes well past the limit"
local f_trunc = write_jsonl({ header_line(), user_msg({ { type = "text", text = long } }) })
local trunc = autoname.first_user_text(f_trunc, 10)
check("first_user_text truncation length", trunc ~= nil and #trunc == 10)
check("first_user_text truncation prefix", trunc == string.sub(long, 1, 10))

local f_none = write_jsonl({ header_line(), assistant_msg({ { type = "text", text = "only assistant" } }) })
check("first_user_text no user message", autoname.first_user_text(f_none, 2000) == nil)

check("first_user_text missing file", autoname.first_user_text(vim.fn.tempname(), 2000) == nil)
check("first_user_text nil file", autoname.first_user_text(nil, 2000) == nil)

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

-- autoname.arm end-to-end with injected runner
local tmp_dir = vim.fn.tempname()
vim.fn.mkdir(tmp_dir, "p")
config.setup({
  auto_name = {
    enabled = true,
    model = "fake/model",
    poll_interval_ms = 10,
    poll_timeout_ms = 2000,
    namer_timeout_ms = 1000,
    max_chars = 2000,
    thinking = "off",
  },
  sessions_dir = tmp_dir,
  agents = {
    pi = { cmd = "true", session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" } },
  },
  start_insert = false,
})
local sessions = require("agent-fleet.sessions")
local id_arm = "arm-e2e-00000001"
local cwd_arm = "/home/test/proj"
local arm_dir = tmp_dir .. "/" .. sessions.cwd_slug(cwd_arm)
vim.fn.mkdir(arm_dir, "p")
local arm_file = arm_dir .. "/20260101_120000_" .. id_arm .. ".jsonl"
vim.fn.writefile({
  vim.json.encode({ type = "session", version = 3, id = id_arm, cwd = cwd_arm }),
  vim.json.encode({
    type = "message",
    message = { role = "user", content = { { type = "text", text = "add billing export" } } },
  }),
}, arm_file)
roster.add({ id = id_arm, type = "pi", name = "pi-9", cwd = cwd_arm, auto_named = true })
local buf_arm = vim.api.nvim_create_buf(false, true)
agent.agents[801] =
  { session_id = id_arm, bufnr = buf_arm, cwd = cwd_arm, name = "pi-9", auto_named = true, agent = "pi" }
local saved_runner = autoname.runner
autoname.runner = function(_argv, _cwd, _timeout, cb)
  cb("Billing Export")
end
autoname.arm({ session_id = id_arm, cwd = cwd_arm, agent = "pi", auto_named = true })
vim.wait(800, function()
  return roster.get(id_arm).name == "Billing Export"
end)
autoname.runner = saved_runner
check("arm e2e renamed", roster.get(id_arm).name == "Billing Export")
check("arm e2e preserves auto_named", roster.get(id_arm).auto_named == true)
agent.agents[801] = nil

-- autoname.arm disabled -> runner never called
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
autoname.arm({ session_id = id_dis, cwd = "/p", agent = "pi", auto_named = true })
vim.wait(100)
autoname.runner = saved_runner2
check("arm disabled runner not called", disabled_called == false)
check("arm disabled no rename", roster.get(id_dis).name == "pi-d")
agent.agents[802] = nil

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
