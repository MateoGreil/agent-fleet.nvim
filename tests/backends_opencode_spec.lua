vim.opt.runtimepath:append(vim.fn.getcwd())

local backends = require("agent-fleet.backends")
local config = require("agent-fleet.config")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

config.setup({ agents = { opencode = {} } })
local c = config.get()
check("opencode preset cmd", c.agents.opencode.cmd == "opencode")
check("opencode preset backend", c.agents.opencode.backend == "opencode")
check("opencode preset resume_flag", c.agents.opencode.session.resume_flag == "--session")
check("opencode preset prompt_flag", c.agents.opencode.session.prompt_flag == "--prompt")
check("opencode preset has no id_flag", c.agents.opencode.session.id_flag == nil)
check("opencode preset has no name_flag", c.agents.opencode.session.name_flag == nil)
check(
  "opencode preset sessions_dir",
  c.agents.opencode.sessions_dir:match("%.local/share/opencode$") ~= nil
)
check("single opencode becomes default", c.default_agent == "opencode")

local oc = backends.resolve("opencode")
check("resolve opencode has_disk true", oc.has_disk == true)
check("resolve opencode list callable", type(oc.list) == "function")
check("resolve opencode session_file callable", type(oc.session_file) == "function")

local ok, err = pcall(function()
local oc = require("agent-fleet.backends.opencode")

check("sql_quote plain", oc.sql_quote("/a/b") == "'/a/b'")
check("sql_quote escapes single quotes", oc.sql_quote("/a'b") == "'/a''b'")
check("sql_quote escapes doubled quotes", oc.sql_quote("x''y") == "'x''''y'")

local q = oc.build_query("/proj/x")
check("query selects session columns", q:find("SELECT s%.id, s%.title, s%.directory, s%.time_created, s%.time_updated", 1, false) ~= nil)
check("query selects last_message", q:find("AS last_message", 1, true) ~= nil)
check("query selects last_part", q:find("AS last_part", 1, true) ~= nil)
check("query filters by directory", q:find("WHERE s%.directory = '/proj/x'", 1, false) ~= nil)
local q2 = oc.build_query("/pro'j/x")
check("query escapes embedded quote", q2:find("WHERE s%.directory = '/pro''j/x'", 1, false) ~= nil)

check("derive no message -> new", oc._derive_state(nil, nil, false) == "new")
check("derive user role -> working", oc._derive_state({ role = "user" }, nil, false) == "working")
check(
  "derive assistant + tool running -> working",
  oc._derive_state({ role = "assistant" }, { type = "tool", state = { status = "running" } }, false) == "working"
)
check(
  "derive assistant + tool pending -> working",
  oc._derive_state({ role = "assistant" }, { type = "tool", state = { status = "pending" } }, false) == "working"
)
check(
  "derive assistant + step-start -> working",
  oc._derive_state({ role = "assistant" }, { type = "step-start" }, false) == "working"
)
check(
  "derive assistant + step-finish -> idle",
  oc._derive_state({ role = "assistant" }, { type = "step-finish" }, false) == "idle"
)
check(
  "derive assistant + text -> idle",
  oc._derive_state({ role = "assistant" }, { type = "text" }, false) == "idle"
)
check(
  "derive assistant + tool completed -> idle",
  oc._derive_state({ role = "assistant" }, { type = "tool", state = { status = "completed" } }, false) == "idle"
)
check(
  "derive assistant + retry -> error",
  oc._derive_state({ role = "assistant" }, { type = "retry" }, false) == "error"
)
check(
  "derive assistant + tool error -> error",
  oc._derive_state({ role = "assistant" }, { type = "tool", state = { status = "error" } }, false) == "error"
)
check(
  "derive corrupt part -> unknown",
  oc._derive_state({ role = "assistant" }, nil, true) == "unknown"
)
check(
  "derive message without role -> working",
  oc._derive_state({}, nil, false) == "working"
)

local function snapshot_row(overrides)
  local row = {
    id = "ses_row1",
    title = "Fix login",
    directory = "/w",
    time_created = 1000,
    time_updated = 2000,
    last_message = '{"role":"assistant"}',
    last_part = '{"type":"step-finish","reason":"stop"}',
  }
  for k, v in pairs(overrides or {}) do
    row[k] = v
  end
  return vim.json.encode(row)
end

local parsed = oc.parse_snapshot("[" .. snapshot_row() .. "]")
check("parse returns one row", parsed ~= nil and #parsed == 1)
check(
  "parse row shape",
  parsed
    and parsed[1].id == "ses_row1"
    and parsed[1].cwd == "/w"
    and parsed[1].created_at == 1000
    and parsed[1].last_activity == 2000
    and parsed[1].title == "Fix login"
    and parsed[1].state == "idle"
)

local parsed_null = oc.parse_snapshot("[" .. snapshot_row({ last_message = vim.NIL, last_part = vim.NIL, id = "ses_null" }) .. "]")
check("parse null message -> new", parsed_null ~= nil and parsed_null[1].state == "new")

local parsed_corrupt = oc.parse_snapshot("[" .. snapshot_row({ last_message = "not json {{{", id = "ses_bad" }) .. "]")
check("parse corrupt message -> unknown", parsed_corrupt ~= nil and parsed_corrupt[1].state == "unknown")

local parsed_multi = oc.parse_snapshot("[" .. snapshot_row() .. "," .. snapshot_row({ id = "ses_row2" }) .. "]")
check("parse keeps order and count", parsed_multi ~= nil and #parsed_multi == 2 and parsed_multi[2].id == "ses_row2")

check("parse rejects non-json", oc.parse_snapshot("not json {{{") == nil)
check("parse rejects json object", oc.parse_snapshot('{"id":"ses_x"}') == nil)
check("parse skips rows without id", #(oc.parse_snapshot('[{"title":"no id"}]') or {}) == 0)
end)
if not ok then
  check(tostring(err), false)
end

local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, "p")
local W = vim.fn.tempname()
vim.fn.mkdir(W, "p")
local stub = stub_dir .. "/opencode"
local fixture = stub_dir .. "/fixture.json"
local log = stub_dir .. "/log"

local function write_stub(body)
  vim.fn.writefile(vim.tbl_flatten({ "#!/usr/bin/env bash", body }), stub)
  vim.fn.setfperm(stub, "rwxr-xr-x")
end

write_stub({
  'printf "%s\\n" "$@" >> "' .. log .. '"',
  'sleep 0.2',
  'cat "' .. fixture .. '"',
})

local function fixture_text(rows)
  return vim.json.encode(rows)
end

local ROW_A = {
  id = "ses_aaa",
  title = "Fix login",
  directory = W,
  time_created = 1000,
  time_updated = 2000,
  last_message = '{"role":"assistant"}',
  last_part = '{"type":"step-finish","reason":"stop"}',
}
local ROW_B = {
  id = "ses_bbb",
  title = "New session - 2026-08-26T10:00:00.000Z",
  directory = W,
  time_created = 3000,
  time_updated = 4000,
  last_message = '{"role":"user"}',
  last_part = nil,
}
vim.fn.writefile({ fixture_text({ ROW_A, ROW_B }) }, fixture)
vim.fn.writefile({ "" }, stub_dir .. "/opencode.db")

config.setup({ agents = { opencode = { cmd = stub, sessions_dir = stub_dir } } })

oc._snapshots = {}
oc._inflight = {}
oc.refresh(W, config.get().agents.opencode)
oc.refresh(W, config.get().agents.opencode)
vim.wait(5000, function()
  return vim.fn.filereadable(log) == 1 and #vim.fn.readfile(log) >= 4
end)
check("in-flight refresh deduped to one query", #vim.fn.readfile(log) == 4)

local snap_ready = false
local ok_wait = vim.wait(5000, function()
  return oc._snapshots[W] ~= nil
end)
check("refresh stored snapshot", ok_wait)

local listed = oc.list(W, config.get().agents.opencode)
check("list returns snapshot rows", #listed == 2 and listed[1].id == "ses_aaa" and listed[2].id == "ses_bbb")
check("list carries derived state", listed[1].state == "idle" and listed[2].state == "working")

oc.refresh(W, config.get().agents.opencode)
check("throttled refresh skips within window", #vim.fn.readfile(log) == 4)

check(
  "session_file returns db path for snapshot id",
  oc.session_file(W, config.get().agents.opencode, "ses_aaa") == stub_dir .. "/opencode.db"
)
check(
  "session_file nil for absent id in warm snapshot",
  oc.session_file(W, config.get().agents.opencode, "ses_missing") == nil
)

vim.fn.delete(log)
oc._snapshots[W] = nil
oc._inflight[W] = nil
vim.fn.writefile({ "" }, stub_dir .. "/opencode.db")
check(
  "session_file optimistic when snapshot cold but db readable",
  oc.session_file(W, config.get().agents.opencode, "ses_anything") == stub_dir .. "/opencode.db"
)

vim.fn.writefile({ "not json" }, fixture)
oc._snapshots[W] = nil
local other = vim.fn.tempname()
vim.fn.mkdir(other, "p")
oc.refresh(other, config.get().agents.opencode)
local ok_wait2 = vim.wait(5000, function()
  return oc._inflight[other] == nil
end)
check("failed parse leaves no snapshot", ok_wait2 and oc._snapshots[other] == nil)
check("list empty after failed snapshot", #oc.list(other, config.get().agents.opencode) == 0)

oc._snapshots = {}
oc._inflight = {}

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
