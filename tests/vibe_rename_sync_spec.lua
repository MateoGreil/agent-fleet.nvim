vim.opt.runtimepath:append(vim.fn.getcwd())

local agent = require("agent-fleet.agent")
local actions = require("agent-fleet.actions")
local backends = require("agent-fleet.backends")
local board = require("agent-fleet.board")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

config.setup({ agents = { vibe = {} } })
local cfg = config.get()
local vibe = backends.resolve("vibe")

local function read_meta(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local raw = fd:read("*a")
  fd:close()
  return raw
end

local function write_meta(root, id, opts)
  local dir = root .. "/unified/" .. id
  vim.fn.mkdir(dir, "p")
  local json = '{"session_id":"' .. id .. '"'
    .. ',"parent_session_id":null'
    .. ',"start_time":' .. (opts.start and ('"' .. opts.start .. '"') or "null")
    .. ',"end_time":null'
    .. ',"origin_directory":"' .. opts.cwd .. '"'
    .. ',"username":"mat"'
    .. ',"title":' .. (opts.title and ('"' .. opts.title .. '"') or "null")
    .. ',"title_source":' .. (opts.tsource and ('"' .. opts.tsource .. '"') or "null")
    .. ',"bumped_at":' .. (opts.bump and ('"' .. opts.bump .. '"') or "null")
    .. ',"archived_at":null'
    .. "}"
  vim.fn.writefile({ json }, dir .. "/meta.json")
  return dir .. "/meta.json"
end

local function find_row(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id then
      return row
    end
  end
  return nil
end

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")
local C = "/proj/vibe-rename"

-- rename_session: disk-only session -> meta.json rewritten, other fields intact
local id_disk = "11111111-2222-4333-8444-555555555555"
local file_disk = write_meta(TMP, id_disk, {
  cwd = C,
  title = "Old Title",
  start = "2026-10-23T10:00:00+00:00",
  bump = "2026-10-23T10:05:00+00:00",
})
vibe.rename_session(cfg.agents.vibe, { id = id_disk, cwd = C, type = "vibe", file = file_disk }, "Board Name")
local meta_disk = vim.json.decode(read_meta(file_disk))
check("rename_session writes title", meta_disk.title == "Board Name")
check("rename_session marks title manual", meta_disk.title_source == "manual")
check("rename_session preserves session_id", meta_disk.session_id == id_disk)
check("rename_session preserves start_time", meta_disk.start_time == "2026-10-23T10:00:00+00:00")
check("rename_session preserves nulls", read_meta(file_disk):match('"parent_session_id":null') ~= nil)
check("rename_session preserves extra fields", meta_disk.username == "mat")

-- rename_session without a file resolves the session via session_file
local id_lookup = "22222222-3333-4444-8555-666666666666"
local file_lookup = write_meta(TMP, id_lookup, {
  cwd = C,
  title = "Lookup Old",
  start = "2026-10-23T10:10:00+00:00",
  bump = "2026-10-23T10:11:00+00:00",
})
vibe.rename_session(
  vim.tbl_extend("force", cfg.agents.vibe, { sessions_dir = TMP }),
  { id = id_lookup, cwd = C, type = "vibe" },
  "Via Lookup"
)
check(
  "rename_session resolves session file when row has no file",
  vim.json.decode(read_meta(file_lookup)).title == "Via Lookup"
)

-- rename_session for a missing session is a no-op (no error)
vibe.rename_session(cfg.agents.vibe, { id = "99999999-9999-4999-8999-999999999999", cwd = C, type = "vibe" }, "Ghost")

-- actions.rename routes to the vibe backend for disk-only rows
roster.add({ id = id_disk, type = "vibe", name = "Board Name", cwd = C, auto_named = true })
actions.rename({ id = id_disk, name = "Board Name", cwd = C, type = "vibe", live = false, file = file_disk }, "From Board")
check("actions.rename updates roster name", roster.get(id_disk) ~= nil and roster.get(id_disk).name == "From Board")
check("actions.rename clears auto_named", roster.get(id_disk).auto_named == false)
check(
  "actions.rename writes vibe meta title",
  vim.json.decode(read_meta(file_disk)).title == "From Board"
)
check(
  "actions.rename writes vibe meta title_source manual",
  vim.json.decode(read_meta(file_disk)).title_source == "manual"
)

-- reconcile: a manual roster name is protected from vibe's automatic titles
local id_prot = "33333333-4444-4555-8666-777777777777"
write_meta(TMP, id_prot, {
  cwd = C,
  title = "Auto Gen",
  tsource = "auto",
  start = "2026-10-23T10:20:00+00:00",
  bump = "2026-10-23T10:21:00+00:00",
})
roster.add({ id = id_prot, type = "vibe", name = "Kept Name", cwd = C, auto_named = false })
vibe.list(C, { sessions_dir = TMP })
check(
  "manual roster name protected from auto vibe title",
  roster.get(id_prot) ~= nil and roster.get(id_prot).name == "Kept Name"
)

-- reconcile: a manual vibe title (vibe /rename) always wins
local id_man = "44444444-5555-4666-8777-888888888888"
write_meta(TMP, id_man, {
  cwd = C,
  title = "Vibe Manual",
  tsource = "manual",
  start = "2026-10-23T10:30:00+00:00",
  bump = "2026-10-23T10:31:00+00:00",
})
roster.add({ id = id_man, type = "vibe", name = "Kept Too", cwd = C, auto_named = false })
vibe.list(C, { sessions_dir = TMP })
check(
  "manual vibe title adopted over manual roster name",
  roster.get(id_man) ~= nil and roster.get(id_man).name == "Vibe Manual"
)
check("manual vibe title clears auto_named", roster.get(id_man).auto_named == false)

-- reconcile: an automatic vibe title is adopted for machine-named entries
local id_auto = "55555555-6666-4777-8888-999999999999"
write_meta(TMP, id_auto, {
  cwd = C,
  title = "Auto Title",
  tsource = "auto",
  start = "2026-10-23T10:40:00+00:00",
  bump = "2026-10-23T10:41:00+00:00",
})
roster.add({ id = id_auto, type = "vibe", name = "prompt derived name", cwd = C, auto_named = true })
vibe.list(C, { sessions_dir = TMP })
check(
  "auto vibe title adopted for auto_named entry",
  roster.get(id_auto) ~= nil and roster.get(id_auto).name == "Auto Title"
)
check("auto adopt keeps auto_named true", roster.get(id_auto).auto_named == true)

-- reconcile: adopted titles update the live agent and its buffer var
local id_live = "66666666-7777-4888-8999-aaaaaaaaaaaa"
write_meta(TMP, id_live, {
  cwd = C,
  title = "Live Sync",
  tsource = "manual",
  start = "2026-10-23T10:50:00+00:00",
  bump = "2026-10-23T10:51:00+00:00",
})
roster.add({ id = id_live, type = "vibe", name = "live old", cwd = C, auto_named = true })
local live_buf = vim.api.nvim_create_buf(false, true)
agent.agents["vrs1"] = {
  id = 91,
  agent = "vibe",
  session_id = id_live,
  cwd = C,
  name = "live old",
  bufnr = live_buf,
}
vim.b[live_buf].agent_fleet = { id = 91, name = "live old", agent = "vibe" }
vibe.list(C, { sessions_dir = TMP })
check("adopt updates live agent name", agent.agents["vrs1"].name == "Live Sync")
check("adopt updates buffer var name", vim.b[live_buf].agent_fleet.name == "Live Sync")
agent.agents["vrs1"] = nil

-- reconcile never creates roster entries for un-rostered disk sessions
check("reconcile leaves un-rostered session un-rostered", roster.get(id_lookup) == nil)

-- board integration: rows carry the synced names
local rows = board.rows({ cwd = C, sessions_dir = TMP, include_archived = true })
local r_man = find_row(rows, id_man)
local r_auto = find_row(rows, id_auto)
local r_prot = find_row(rows, id_prot)
check("board row shows adopted manual vibe title", r_man ~= nil and r_man.name == "Vibe Manual")
check("board row shows adopted auto vibe title", r_auto ~= nil and r_auto.name == "Auto Title")
check("board row keeps protected manual roster name", r_prot ~= nil and r_prot.name == "Kept Name")

-- rename_session: live chansend path sanitizes the name and defers meta adoption
local id_job = "77777777-8888-4999-9aaa-bbbbbbbbbbbb"
local file_job = write_meta(TMP, id_job, {
  cwd = C,
  title = "Job Old",
  start = "2026-10-23T11:00:00+00:00",
  bump = "2026-10-23T11:01:00+00:00",
})
local captured = {}
local job = vim.fn.jobstart({ "cat" }, {
  on_stdout = function(_, data)
    for _, line in ipairs(data) do
      captured[#captured + 1] = line
    end
  end,
})
local job_buf = vim.api.nvim_create_buf(false, true)
agent.agents["vrs-job"] = {
  id = 92,
  agent = "vibe",
  session_id = id_job,
  cwd = C,
  name = "Job Old",
  bufnr = job_buf,
  job = job,
}
vibe.rename_session(cfg.agents.vibe, { id = id_job, cwd = C, type = "vibe", file = file_job }, "Live\nRenamed")
vim.wait(2000, function()
  return #captured > 0
end)
local sent_out = table.concat(captured, "\n")
check("chansend sends sanitized /rename", sent_out:match("/rename Live Renamed") ~= nil)
check("chansend name has no embedded newline", sent_out:match("Live\n") == nil and sent_out:match("\nRenamed") == nil)
check("chansend leaves meta.json untouched", vim.json.decode(read_meta(file_job)).title == "Job Old")
check("chansend records pending rename", vibe._pending_renames[id_job] == "Live Renamed")
vim.fn.jobstop(job)
agent.agents["vrs-job"] = nil

-- reconcile: a pending chansend rename blocks adoption of the stale manual title
local id_pend = "88888888-9999-4aaa-8bbb-cccccccccccc"
write_meta(TMP, id_pend, {
  cwd = C,
  title = "Manual A",
  tsource = "manual",
  start = "2026-10-23T11:10:00+00:00",
  bump = "2026-10-23T11:11:00+00:00",
})
roster.add({ id = id_pend, type = "vibe", name = "Board B", cwd = C, auto_named = false })
vibe._pending_renames[id_pend] = "Board B"
local pend_buf = vim.api.nvim_create_buf(false, true)
agent.agents["vrs-pend"] = {
  id = 93,
  agent = "vibe",
  session_id = id_pend,
  cwd = C,
  name = "Board B",
  bufnr = pend_buf,
}
vibe.list(C, { sessions_dir = TMP })
check("pending guard blocks stale title adoption", roster.get(id_pend) ~= nil and roster.get(id_pend).name == "Board B")
check("pending guard keeps pending entry", vibe._pending_renames[id_pend] == "Board B")

write_meta(TMP, id_pend, {
  cwd = C,
  title = "Board B",
  tsource = "manual",
  start = "2026-10-23T11:10:00+00:00",
  bump = "2026-10-23T11:12:00+00:00",
})
vibe.list(C, { sessions_dir = TMP })
check("pending entry cleared once meta matches", vibe._pending_renames[id_pend] == nil)
check("roster keeps board name after pending clears", roster.get(id_pend) ~= nil and roster.get(id_pend).name == "Board B")

agent.agents["vrs-pend"] = nil
vibe._pending_renames[id_pend] = "Board B"
write_meta(TMP, id_pend, {
  cwd = C,
  title = "Manual A",
  tsource = "manual",
  start = "2026-10-23T11:10:00+00:00",
  bump = "2026-10-23T11:13:00+00:00",
})
vibe.list(C, { sessions_dir = TMP })
check("pending falls through to adoption without live agent", roster.get(id_pend) ~= nil and roster.get(id_pend).name == "Manual A")
check("pending cleared without live agent", vibe._pending_renames[id_pend] == nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
