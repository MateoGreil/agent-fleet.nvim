vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local board = require("agent-fleet.board")
local roster = require("agent-fleet.roster")
local sessions = require("agent-fleet.sessions")
local agent = require("agent-fleet.agent")
local util = require("agent-fleet.util")

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

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")

local function write_session(cwd, id, ts)
  local dir = TMP .. "/" .. sessions.cwd_slug(cwd)
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. ts .. "_" .. id .. ".jsonl"
  local header = string.format(
    '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}',
    id,
    ts,
    cwd
  )
  vim.fn.writefile({ header }, file)
  return file
end

local function msg(ts, role, stop_reason)
  local m = { role = role }
  if stop_reason then
    m.stopReason = stop_reason
  end
  return vim.json.encode({ type = "message", timestamp = ts, message = m })
end

local function write_session_events(cwd, id, ts, events)
  local dir = TMP .. "/" .. sessions.cwd_slug(cwd)
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. ts .. "_" .. id .. ".jsonl"
  local lines = {
    string.format(
      '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}',
      id,
      ts,
      cwd
    ),
  }
  for _, e in ipairs(events) do
    lines[#lines + 1] = e
  end
  vim.fn.writefile(lines, file)
  return file
end

-- Case 1: roster-only entry
local C1 = "/proj/c1"
local id1 = "11111111-1111-1111-1111-111111111111"
roster.add({ id = id1, type = "pi", name = "roster-named", cwd = C1 })
local rows1 = board.rows({ cwd = C1, sessions_dir = TMP })
local r1 = find_row(rows1, id1)
check("case1 roster-only appears", r1 ~= nil)
check("case1 live false", r1 and r1.live == false)
check("case1 file nil", r1 and r1.file == nil)
check("case1 name from roster", r1 and r1.name == "roster-named")
check("case1 done/archived false", r1 and r1.done == false and r1.archived == false)

-- Case 2: disk-only session
local C2 = "/proj/c2"
local id2 = "22222222-2222-2222-2222-222222222222"
local f2 = write_session(C2, id2, "2026-02-02T00:00:00.000Z")
local rows2 = board.rows({ cwd = C2, sessions_dir = TMP })
local r2 = find_row(rows2, id2)
check("case2 disk-only appears", r2 ~= nil)
check("case2 live false", r2 and r2.live == false)
check("case2 name derived", r2 and r2.name == "pi:" .. id2:sub(1, 8))
check("case2 file set", r2 and r2.file == f2)

-- Case 3: id in both live registry AND disk -> one deduped row
local C3 = "/proj/c3"
local id3 = "33333333-3333-3333-3333-333333333333"
local f3 = write_session(C3, id3, "2026-03-03T00:00:00.000Z")
local buf3 = vim.api.nvim_create_buf(false, true)
agent.agents["k3"] = { session_id = id3, bufnr = buf3, cwd = C3, name = "live-one" }
local rows3 = board.rows({ cwd = C3, sessions_dir = TMP })
local count3 = 0
for _, row in ipairs(rows3) do
  if row.id == id3 then
    count3 = count3 + 1
  end
end
local r3 = find_row(rows3, id3)
check("case3 single deduped row", count3 == 1)
check("case3 live true", r3 and r3.live == true)
check("case3 bufnr set", r3 and r3.bufnr == buf3)
check("case3 file set", r3 and r3.file == f3)

-- Case 4: archived roster entry excluded by default, included on demand
local C4 = "/proj/c4"
local id4 = "44444444-4444-4444-4444-444444444444"
roster.add({ id = id4, type = "pi", name = "arch", cwd = C4 })
roster.set_archived(id4, true)
local rows4_default = board.rows({ cwd = C4, sessions_dir = TMP })
local rows4_incl = board.rows({ cwd = C4, sessions_dir = TMP, include_archived = true })
check("case4 archived excluded by default", find_row(rows4_default, id4) == nil)
local r4 = find_row(rows4_incl, id4)
check("case4 archived included on demand", r4 ~= nil and r4.archived == true)

-- Case 5: ordering = live-active, dead-active, done, archived
local CO = "/proj/order"
local id_live = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local id_dead = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local id_done = "cccccccc-cccc-cccc-cccc-cccccccccccc"
local id_arch = "dddddddd-dddd-dddd-dddd-dddddddddddd"
roster.add({ id = id_live, type = "pi", name = "o-live", cwd = CO })
roster.add({ id = id_dead, type = "pi", name = "o-dead", cwd = CO })
roster.add({ id = id_done, type = "pi", name = "o-done", cwd = CO })
roster.mark_done(id_done)
roster.add({ id = id_arch, type = "pi", name = "o-arch", cwd = CO })
roster.set_archived(id_arch, true)
local buf_o = vim.api.nvim_create_buf(false, true)
agent.agents["ko"] = { session_id = id_live, bufnr = buf_o, cwd = CO, name = "o-live" }
local rows5 = board.rows({ cwd = CO, sessions_dir = TMP, include_archived = true })
check(
  "case5 ordering",
  #rows5 == 4
    and rows5[1].id == id_live
    and rows5[2].id == id_dead
    and rows5[3].id == id_done
    and rows5[4].id == id_arch
)

-- Case 6: cwd filtering excludes other-cwd roster and disk entries
local CMain = "/proj/main"
local COther = "/proj/other"
local id_other_roster = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
local id_other_disk = "ffffffff-ffff-ffff-ffff-ffffffffffff"
roster.add({ id = id_other_roster, type = "pi", name = "other-r", cwd = COther })
write_session(COther, id_other_disk, "2026-06-06T00:00:00.000Z")
local rows6 = board.rows({ cwd = CMain, sessions_dir = TMP, include_archived = true })
check("case6 other roster excluded", find_row(rows6, id_other_roster) == nil)
check("case6 other disk excluded", find_row(rows6, id_other_disk) == nil)

-- Case 7: rows carry derived state + last_activity
local C7 = "/proj/c7"
local id7s = "77777777-7777-7777-7777-777777777771"
write_session_events(C7, id7s, "2026-07-01T00:00:00.000Z", {
  msg("2026-07-01T00:05:00.000Z", "assistant", "stop"),
})
local id7n = "77777777-7777-7777-7777-777777777772"
roster.add({ id = id7n, type = "pi", name = "no-file", cwd = C7 })
local rows7 = board.rows({ cwd = C7, sessions_dir = TMP })
local r7s = find_row(rows7, id7s)
local r7n = find_row(rows7, id7n)
check("case7 disk row state idle", r7s ~= nil and r7s.state == "idle")
check(
  "case7 disk row last_activity positive number",
  r7s ~= nil and type(r7s.last_activity) == "number" and r7s.last_activity > 0
)
check("case7 no-file row state new", r7n ~= nil and r7n.state == "new")
check("case7 no-file row file nil", r7n ~= nil and r7n.file == nil)
check(
  "case7 no-file row last_activity == created_at",
  r7n ~= nil and r7n.last_activity == r7n.created_at
)

-- Case 8: sort by last_activity desc (within the same group)
local C8 = "/proj/c8"
local id8_old = "88888888-8888-8888-8888-888888888881"
local id8_new = "88888888-8888-8888-8888-888888888882"
write_session_events(C8, id8_old, "2026-08-01T00:00:00.000Z", {
  msg("2026-08-01T00:10:00.000Z", "assistant", "stop"),
})
write_session_events(C8, id8_new, "2026-08-02T00:00:00.000Z", {
  msg("2026-08-09T00:00:00.000Z", "assistant", "stop"),
})
local rows8 = board.rows({ cwd = C8, sessions_dir = TMP })
local idx_old, idx_new
for i, row in ipairs(rows8) do
  if row.id == id8_old then
    idx_old = i
  elseif row.id == id8_new then
    idx_new = i
  end
end
check(
  "case8 more recently active sorts first",
  idx_old ~= nil and idx_new ~= nil and idx_new < idx_old
)

-- Case 9: format_row rich one-line rendering
local NOW = 2000000000 * 1000
local row_live = {
  id = "f1",
  name = "my-agent",
  cwd = "/p",
  live = true,
  done = false,
  archived = false,
  state = "idle",
  last_activity = NOW - 5 * 60 * 1000,
}
local s_live = board.format_row(row_live, NOW)
check("case9 contains state word", s_live:find("idle", 1, true) ~= nil)
check("case9 contains name", s_live:find("my-agent", 1, true) ~= nil)
check(
  "case9 contains relative time",
  s_live:find(util.relative_time(row_live.last_activity, NOW), 1, true) ~= nil
)
check("case9 live marker", s_live:find("\u{25cf}", 1, true) ~= nil)
check("case9 no checkmark when not done", s_live:find("\u{2713}", 1, true) == nil)
check("case9 no archived prefix", s_live:sub(1, #"[archived]") ~= "[archived]")

local row_da = {
  id = "f2",
  name = "older",
  cwd = "/p",
  live = false,
  done = true,
  archived = true,
  state = "stopped",
  last_activity = NOW - 3 * 3600 * 1000,
}
local s_da = board.format_row(row_da, NOW)
check("case9 not-live marker", s_da:find("\u{25cb}", 1, true) ~= nil)
check("case9 checkmark when done", s_da:find("\u{2713}", 1, true) ~= nil)
check("case9 archived prefix", s_da:sub(1, #"[archived]") == "[archived]")
check("case9 contains stopped state", s_da:find("stopped", 1, true) ~= nil)

local long_name = string.rep("z", 30)
local row_long = {
  id = "f3",
  name = long_name,
  cwd = "/p",
  live = false,
  done = false,
  archived = false,
  state = "new",
  last_activity = NOW,
}
local s_long = board.format_row(row_long, NOW)
check(
  "case9 long name truncated with ellipsis",
  s_long:find(long_name:sub(1, 21) .. "\u{2026}", 1, true) ~= nil
    and s_long:find(long_name, 1, true) == nil
)

local accent_name = string.rep("\u{e9}", 30)
local row_accent = {
  id = "f4",
  name = accent_name,
  cwd = "/p",
  live = false,
  done = false,
  archived = false,
  state = "new",
  last_activity = NOW,
}
local s_accent = board.format_row(row_accent, NOW)
check(
  "case9 multibyte name truncated on codepoint boundary",
  s_accent:find(string.rep("\u{e9}", 21) .. "\u{2026}", 1, true) ~= nil
    and s_accent:find(accent_name, 1, true) == nil
)

local row_zero = {
  id = "f5",
  name = "n",
  cwd = "/p",
  live = false,
  done = false,
  archived = false,
  state = "new",
  last_activity = 0,
}
local s_zero = board.format_row(row_zero, NOW)
check("case9 zero activity renders em-dash", s_zero:find("\u{2014}", 1, true) ~= nil)
check("case9 zero activity no bogus week count", s_zero:find("%d+w") == nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
