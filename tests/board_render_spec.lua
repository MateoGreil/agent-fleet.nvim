vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local board = require("agent-fleet.board")
local util = require("agent-fleet.util")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function line_index(lines, needle)
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      return i
    end
  end
  return nil
end

local function hl_for(highlights, line0, group)
  for _, h in ipairs(highlights) do
    if h.line == line0 and h.hl_group == group then
      return h
    end
  end
  return nil
end

local NOW = 2000000000 * 1000

local live_row =
  { id = "L", name = "live-agent", live = true, done = false, archived = false, state = "working", last_activity = NOW - 60000 }
local idle_row =
  { id = "I", name = "idle-agent", live = false, done = false, archived = false, state = "idle", last_activity = NOW - 3600000 }
local done_row =
  { id = "D", name = "done-agent", live = false, done = true, archived = false, state = "stopped", last_activity = NOW - 7200000 }
local arch_row =
  { id = "A", name = "arch-agent", live = false, done = false, archived = true, state = "idle", last_activity = NOW - 86400000 }

-- Test 1: section grouping & order, counts, archived visibility
local r1 = board.render({ live_row, idle_row, done_row, arch_row }, { now_ms = NOW, cwd = "/p", show_archived = true })
local ri = line_index(r1.lines, "RUNNING")
local ii = line_index(r1.lines, "IDLE")
local di = line_index(r1.lines, "DONE")
local ai = line_index(r1.lines, "ARCHIVED")
check("t1 order RUNNING<IDLE<DONE<ARCHIVED", ri and ii and di and ai and ri < ii and ii < di and di < ai)
check("t1 RUNNING count 1", line_index(r1.lines, "RUNNING  1") ~= nil)
check("t1 IDLE count 1", line_index(r1.lines, "IDLE  1") ~= nil)
check("t1 DONE count 1", line_index(r1.lines, "DONE  1") ~= nil)
check("t1 ARCHIVED count 1", line_index(r1.lines, "ARCHIVED  1") ~= nil)

local r1h = board.render({ live_row, idle_row, done_row, arch_row }, { now_ms = NOW, cwd = "/p", show_archived = false })
check("t1 archived header hidden", line_index(r1h.lines, "ARCHIVED") == nil)
check("t1 archived row hidden", line_index(r1h.lines, "arch-agent") == nil)

-- Test 2: empty sections omitted
local r2 = board.render({ live_row, done_row }, { now_ms = NOW, cwd = "/p" })
check("t2 no IDLE header", line_index(r2.lines, "IDLE") == nil)
check("t2 RUNNING present", line_index(r2.lines, "RUNNING") ~= nil)
check("t2 DONE present", line_index(r2.lines, "DONE") ~= nil)

-- Test 3: row column content
local r3 = board.render({ live_row }, { now_ms = NOW, cwd = "/p" })
local rowline = r3.lines[2]
check("t3 live marker", rowline:find("\u{25cf}", 1, true) ~= nil)
check("t3 state word present", rowline:find("working", 1, true) ~= nil)
check("t3 name present", rowline:find("live-agent", 1, true) ~= nil)
check("t3 relative time present", rowline:find(util.relative_time(live_row.last_activity, NOW), 1, true) ~= nil)

local zero_row =
  { id = "Z", name = "zero", live = false, done = false, archived = false, state = "idle", last_activity = 0 }
local r3z = board.render({ zero_row }, { now_ms = NOW, cwd = "/p" })
check("t3 not-live marker", r3z.lines[2]:find("\u{25cb}", 1, true) ~= nil)
check("t3 em-dash for zero activity", r3z.lines[2]:find("\u{2014}", 1, true) ~= nil)

local nil_row =
  { id = "N", name = "niltime", live = false, done = false, archived = false, state = "idle", last_activity = nil }
local r3n = board.render({ nil_row }, { now_ms = NOW, cwd = "/p" })
check("t3 em-dash for nil activity", r3n.lines[2]:find("\u{2014}", 1, true) ~= nil)

-- Test 4: char-aware name truncation at 28
local long = string.rep("z", 30)
local long_row =
  { id = "T", name = long, live = false, done = false, archived = false, state = "idle", last_activity = NOW }
local r4 = board.render({ long_row }, { now_ms = NOW, cwd = "/p" })
check(
  "t4 ascii truncated",
  r4.lines[2]:find(long:sub(1, 27) .. "\u{2026}", 1, true) ~= nil and r4.lines[2]:find(long, 1, true) == nil
)

local accent = string.rep("\u{e9}", 30)
local accent_row =
  { id = "TA", name = accent, live = false, done = false, archived = false, state = "idle", last_activity = NOW }
local r4a = board.render({ accent_row }, { now_ms = NOW, cwd = "/p" })
check(
  "t4 multibyte truncated on boundary",
  r4a.lines[2]:find(string.rep("\u{e9}", 27) .. "\u{2026}", 1, true) ~= nil
    and r4a.lines[2]:find(accent, 1, true) == nil
)

-- Test 5: line_to_row indexing (1-indexed; headers/blanks absent)
local r5 = board.render({ idle_row }, { now_ms = NOW, cwd = "/p" })
check("t5 header line 1 absent from map", r5.line_to_row[1] == nil)
check("t5 row line 2 maps to row", r5.line_to_row[2] == idle_row)

-- Test 6: highlights
local r6 = board.render({ live_row }, { now_ms = NOW, cwd = "/p" })
local hs = hl_for(r6.highlights, 1, "AgentFleetWorking")
check("t6 state highlight group", hs ~= nil)
check("t6 state highlight line 0-indexed", hs and hs.line == 1)
check("t6 state byte range exact", hs and r6.lines[2]:sub(hs.col_start + 1, hs.col_end) == "working")
local ht = hl_for(r6.highlights, 1, "AgentFleetTime")
local timeword = util.relative_time(live_row.last_activity, NOW)
check("t6 time highlight present", ht ~= nil)
check("t6 time byte range exact", ht and r6.lines[2]:sub(ht.col_start + 1, ht.col_end) == timeword)

local r6a = board.render({ arch_row }, { now_ms = NOW, cwd = "/p", show_archived = true })
local ha = hl_for(r6a.highlights, 1, "AgentFleetArchived")
check("t6 archived whole-line highlight", ha ~= nil and ha.col_start == 0 and ha.col_end == -1)
check(
  "t6 archived no per-column",
  hl_for(r6a.highlights, 1, "AgentFleetIdle") == nil and hl_for(r6a.highlights, 1, "AgentFleetTime") == nil
)

local r6u =
  board.render({ { id = "U", name = "u", live = false, done = false, archived = false, state = "bogus", last_activity = NOW } }, { now_ms = NOW, cwd = "/p" })
check("t6 unknown state falls back to New", hl_for(r6u.highlights, 1, "AgentFleetNew") ~= nil)

-- Test 7: empty state
local r7 = board.render({}, { now_ms = NOW, cwd = "/my/dir", show_archived = false })
check("t7 title present", line_index(r7.lines, "agent-fleet \u{00b7} /my/dir") ~= nil)
check("t7 placeholder present", line_index(r7.lines, "No agents in this directory.") ~= nil)
check("t7 launch hint present", line_index(r7.lines, "to launch with a prompt") ~= nil)
check("t7 empty line_to_row", next(r7.line_to_row) == nil)
check("t7 title header highlight", hl_for(r7.highlights, 0, "AgentFleetHeader") ~= nil)

local r7c = board.render({}, { now_ms = NOW, cwd = "/d", show_archived = false, archived_count = 3 })
check("t7 archived hint mentions N (opts)", line_index(r7c.lines, "3 archived") ~= nil)

local r7r = board.render({ arch_row }, { now_ms = NOW, cwd = "/d", show_archived = false })
check("t7 all-archived hidden -> empty", line_index(r7r.lines, "No agents in this directory.") ~= nil)
check("t7 archived hint mentions N (from rows)", line_index(r7r.lines, "1 archived") ~= nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
