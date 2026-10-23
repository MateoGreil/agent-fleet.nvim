vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local backends = require("agent-fleet.backends")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

config.setup({ agents = { vibe = {} } })
local cfg = config.get()
check("vibe preset cmd", cfg.agents.vibe.cmd == "vibe")
check("vibe preset backend", cfg.agents.vibe.backend == "vibe")
check(
  "vibe preset sessions_dir ends with .vibe/logs/session",
  cfg.agents.vibe.sessions_dir ~= nil and cfg.agents.vibe.sessions_dir:match("%.vibe/logs/session$") ~= nil
)
local vs = cfg.agents.vibe.session
check("vibe preset resume_flag", type(vs) == "table" and vs.resume_flag == "--resume")
check("vibe preset prompt_positional", type(vs) == "table" and vs.prompt_positional == true)
check("vibe preset no id_flag", type(vs) == "table" and vs.id_flag == nil)
check("vibe preset no name_flag", type(vs) == "table" and vs.name_flag == nil)
check("single vibe becomes default", cfg.default_agent == "vibe")

local vibe = backends.resolve("vibe")
check("resolve vibe has_disk true", vibe.has_disk == true)
check("resolve vibe list callable", type(vibe.list) == "function")
check("resolve vibe tail_info callable", type(vibe.tail_info) == "function")
check("resolve vibe session_file callable", type(vibe.session_file) == "function")

local function utc_ms(y, mo, d, h, mi, s, ms)
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  t = t - os.difftime(os.time(os.date("!*t", t)), t)
  return t * 1000 + (ms or 0)
end

local function write_meta(root, id, opts)
  local dir = root .. "/unified/" .. id
  vim.fn.mkdir(dir, "p")
  local arch = ""
  if opts.arch then
    arch = ',"archived_at":' .. (opts.arch == "null" and "null" or ('"' .. opts.arch .. '"'))
  end
  local json = '{"session_id":"' .. id .. '"'
    .. ',"parent_session_id":' .. (opts.parent and ('"' .. opts.parent .. '"') or "null")
    .. ',"start_time":' .. (opts.start and ('"' .. opts.start .. '"') or "null")
    .. ',"end_time":' .. (opts.endt and ('"' .. opts.endt .. '"') or "null")
    .. ',"origin_directory":"' .. opts.cwd .. '"'
    .. ',"title":' .. (opts.title and ('"' .. opts.title .. '"') or "null")
    .. ',"bumped_at":' .. (opts.bump and ('"' .. opts.bump .. '"') or "null")
    .. arch
    .. "}"
  vim.fn.writefile({ json }, dir .. "/meta.json")
  return dir .. "/meta.json"
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local cwd = "/test/project"
local uuid_a = "11111111-1111-4111-8111-111111111111"
local uuid_b = "22222222-2222-4222-8222-222222222222"
local uuid_c = "33333333-3333-4333-8333-333333333333"
local uuid_d = "44444444-4444-4444-8444-444444444444"
local uuid_e = "55555555-5555-4555-8555-555555555555"
local uuid_f = "66666666-6666-4666-8666-666666666666"

local file_a = write_meta(tmp, uuid_a, {
  cwd = cwd,
  title = "Fix flaky test",
  start = "2026-10-22T14:48:57+00:00",
  bump = "2026-10-22T14:49:13.758983+00:00",
})
local file_b = write_meta(tmp, uuid_b, {
  cwd = cwd,
  title = "Write docs",
  start = "2026-10-22T16:50:00+02:00",
  bump = "2026-10-22T14:51:30.100000+00:00",
  endt = "2026-10-22T14:51:30.926000+00:00",
})
write_meta(tmp, uuid_c, {
  cwd = "/other/project",
  title = "Elsewhere",
  start = "2026-10-22T14:40:00+00:00",
  bump = "2026-10-22T14:40:00+00:00",
  endt = "2026-10-22T14:40:00+00:00",
})
write_meta(tmp, uuid_d, {
  cwd = cwd,
  parent = uuid_a,
  title = "Child",
  start = "2026-10-22T14:45:00+00:00",
  bump = "2026-10-22T14:45:00+00:00",
})
local dir_e = tmp .. "/unified/" .. uuid_e
vim.fn.mkdir(dir_e, "p")
local file_e = dir_e .. "/meta.json"
vim.fn.writefile({ "{ not valid json" }, file_e)
local file_f = write_meta(tmp, uuid_f, {
  cwd = cwd,
  start = "2026-10-22T14:52:00+00:00",
  bump = "2026-10-22T14:52:00+00:00",
})

local rows = vibe.list(cwd, { sessions_dir = tmp })
check("list returns 3 matching sessions", type(rows) == "table" and #rows == 3)
check("list row 1 id", rows[1] ~= nil and rows[1].id == uuid_a)
check("list row 1 cwd", rows[1] ~= nil and rows[1].cwd == cwd)
check("list row 1 title from meta", rows[1] ~= nil and rows[1].title == "Fix flaky test")
check("list row 1 state working (end_time null)", rows[1] ~= nil and rows[1].state == "working")
check("list row 1 file is meta.json path", rows[1] ~= nil and rows[1].file == file_a and vim.fn.filereadable(rows[1].file) == 1)
check("list row 1 created_at epoch ms (+00:00 form)", rows[1] ~= nil and rows[1].created_at == utc_ms(2026, 10, 22, 14, 48, 57, 0))
check("list row 1 last_activity epoch ms fractional", rows[1] ~= nil and rows[1].last_activity == utc_ms(2026, 10, 22, 14, 49, 13, 758))
check("list row 2 id", rows[2] ~= nil and rows[2].id == uuid_b)
check("list row 2 state idle (end_time set)", rows[2] ~= nil and rows[2].state == "idle")
check("list row 2 created_at epoch ms (+02:00 offset form)", rows[2] ~= nil and rows[2].created_at == utc_ms(2026, 10, 22, 14, 50, 0))
check("list row 2 last_activity epoch ms", rows[2] ~= nil and rows[2].last_activity == utc_ms(2026, 10, 22, 14, 51, 30, 100))
check("list row 3 id", rows[3] ~= nil and rows[3].id == uuid_f)
check("list row 3 title fallback when null", rows[3] ~= nil and rows[3].title == "vibe:66666666")
check(
  "list sorted by created_at ascending",
  rows[1] ~= nil and rows[3] ~= nil and rows[1].created_at <= rows[2].created_at and rows[2].created_at <= rows[3].created_at
)
local ids = {}
for _, row in ipairs(rows) do
  ids[row.id] = true
end
check("list skips session from another cwd", ids[uuid_c] == nil)
check("list skips child session (parent_session_id set)", ids[uuid_d] == nil)
check("list skips malformed meta.json without failing scan", ids[uuid_e] == nil)

local info_a = vibe.tail_info(file_a)
check("tail_info working state", info_a ~= nil and info_a.state == "working")
check("tail_info last_activity", info_a ~= nil and info_a.last_activity == utc_ms(2026, 10, 22, 14, 49, 13, 758))
local info_b = vibe.tail_info(file_b)
check("tail_info idle state", info_b ~= nil and info_b.state == "idle")
check("tail_info nil for unreadable file", vibe.tail_info("/nonexistent/session/meta.json") == nil)
check("tail_info nil for malformed meta.json", vibe.tail_info(file_e) == nil)
check("tail_info nil for nil file", vibe.tail_info(nil) == nil)

local found = vibe.session_file(cwd, { sessions_dir = tmp }, uuid_a)
check("session_file found", found ~= nil and found == file_a)
local missing = vibe.session_file(cwd, { sessions_dir = tmp }, "99999999-9999-4999-8999-999999999999")
check("session_file missing returns nil", missing == nil)

local empty = vibe.list(cwd, { sessions_dir = "/nonexistent-vibe-sessions" })
check("list on nonexistent sessions_dir returns empty table", type(empty) == "table" and #empty == 0)

local function roster_count(rcwd, id)
  local n = 0
  for _, entry in ipairs(roster.list({ cwd = rcwd, include_archived = true })) do
    if entry.id == id then
      n = n + 1
    end
  end
  return n
end

local bind_dir = vim.fn.tempname()
vim.fn.mkdir(bind_dir, "p")
local bind_cwd = "/test/bind-project"
local bind_spawn_ms = utc_ms(2026, 10, 22, 15, 0, 0, 0)
local bind_buf = vim.api.nvim_create_buf(false, true)
local uuid_g = "77777777-7777-4777-8777-777777777777"
local uuid_h = "88888888-8888-4888-8888-888888888888"
local uuid_i = "99999999-9999-4999-8999-999999999999"
local uuid_j = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

local function fake_vibe_agent(key, num, name)
  agent.agents[key] = {
    id = num,
    agent = "vibe",
    session_id = nil,
    cwd = bind_cwd,
    name = name,
    spawned_ms = bind_spawn_ms,
    bufnr = bind_buf,
  }
end

write_meta(bind_dir, uuid_g, {
  cwd = bind_cwd,
  start = "2026-10-22T15:00:02+00:00",
  bump = "2026-10-22T15:00:02+00:00",
})
fake_vibe_agent("vb1", 71, "vibe-live-one")
vibe.list(bind_cwd, { sessions_dir = bind_dir })
check("bind: session within tolerance binds agent", agent.agents["vb1"].session_id == uuid_g)
local bound_entry = roster.get(uuid_g)
check("bind: roster entry created", bound_entry ~= nil)
check("bind: roster entry carries agent name", bound_entry ~= nil and bound_entry.name == "vibe-live-one")
check("bind: roster entry type vibe", bound_entry ~= nil and bound_entry.type == "vibe")
check("bind: roster entry cwd", bound_entry ~= nil and bound_entry.cwd == bind_cwd)

vibe.list(bind_cwd, { sessions_dir = bind_dir })
check("bind: repeat list keeps agent bound", agent.agents["vb1"].session_id == uuid_g)
check("bind: repeat list adds no duplicate roster entry", roster_count(bind_cwd, uuid_g) == 1)
agent.agents["vb1"] = nil

write_meta(bind_dir, uuid_h, {
  cwd = bind_cwd,
  start = "2026-10-22T14:59:53+00:00",
  bump = "2026-10-22T14:59:53+00:00",
})
fake_vibe_agent("vb2", 72, "vibe-live-two")
vibe.list(bind_cwd, { sessions_dir = bind_dir })
check("bind: session older than tolerance not bound", agent.agents["vb2"].session_id == nil)
check("bind: out-of-tolerance session not rostered", roster.get(uuid_h) == nil)
agent.agents["vb2"] = nil

write_meta(bind_dir, uuid_i, {
  cwd = bind_cwd,
  start = "2026-10-22T14:59:55+00:00",
  bump = "2026-10-22T14:59:55+00:00",
})
fake_vibe_agent("vb3", 73, "vibe-live-three")
vibe.list(bind_cwd, { sessions_dir = bind_dir })
check("bind: session exactly at tolerance edge binds", agent.agents["vb3"].session_id == uuid_i)
local edge_entry = roster.get(uuid_i)
check("bind: tolerance edge roster entry has agent name", edge_entry ~= nil and edge_entry.name == "vibe-live-three")
agent.agents["vb3"] = nil

write_meta(bind_dir, uuid_j, {
  cwd = bind_cwd,
  start = "2026-10-22T15:00:01+00:00",
  bump = "2026-10-22T15:00:01+00:00",
})
roster.add({ id = uuid_j, type = "vibe", name = "pre-claimed", cwd = bind_cwd })
fake_vibe_agent("vb4", 74, "vibe-live-four")
vibe.list(bind_cwd, { sessions_dir = bind_dir })
check("bind: already rostered session not bound to new agent", agent.agents["vb4"].session_id == nil)
check("bind: already rostered session not duplicated", roster_count(bind_cwd, uuid_j) == 1)
check("bind: pre-claimed roster name preserved", roster.get(uuid_j) ~= nil and roster.get(uuid_j).name == "pre-claimed")
agent.agents["vb4"] = nil

check(
  "bind: roster holds exactly bound and pre-claimed sessions",
  #roster.list({ cwd = bind_cwd, include_archived = true }) == 3
)

local arch_dir = vim.fn.tempname()
vim.fn.mkdir(arch_dir, "p")
local arch_cwd = "/test/vibe-archived"
local uuid_k = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
local uuid_l = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
local uuid_m = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
write_meta(arch_dir, uuid_k, {
  cwd = arch_cwd,
  title = "Still active",
  start = "2026-10-22T15:10:00+00:00",
  bump = "2026-10-22T15:10:00+00:00",
  arch = "null",
})
write_meta(arch_dir, uuid_l, {
  cwd = arch_cwd,
  title = "Packed up",
  start = "2026-10-22T15:11:00+00:00",
  bump = "2026-10-22T15:11:00+00:00",
  arch = "2026-10-23T09:00:00+00:00",
})
write_meta(arch_dir, uuid_m, {
  cwd = arch_cwd,
  title = "Legacy meta",
  start = "2026-10-22T15:12:00+00:00",
  bump = "2026-10-22T15:12:00+00:00",
})
local arch_rows = vibe.list(arch_cwd, { sessions_dir = arch_dir })
local function arch_row(rid)
  for _, r in ipairs(arch_rows) do
    if r.id == rid then
      return r
    end
  end
  return nil
end
check("archived: list returns 3 sessions", #arch_rows == 3)
check(
  "archived: timestamp meta marks row archived",
  arch_row(uuid_l) ~= nil and arch_row(uuid_l).archived == true
)
check(
  "archived: json null meta leaves row archived nil",
  arch_row(uuid_k) ~= nil and arch_row(uuid_k).archived == nil
)
check(
  "archived: absent field leaves row archived nil",
  arch_row(uuid_m) ~= nil and arch_row(uuid_m).archived == nil
)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
