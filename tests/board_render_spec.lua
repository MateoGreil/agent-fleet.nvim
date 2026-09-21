vim.opt.runtimepath:append(vim.fn.getcwd())

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
local child_row = {
  id = "C",
  name = "child-agent",
  live = false,
  done = false,
  archived = false,
  state = "idle",
  last_activity = NOW - 1800000,
  parent_session = "/sessions/parent.jsonl",
}
local archived_child_row = {
  id = "AC",
  name = "archived-child-agent",
  live = false,
  done = false,
  archived = true,
  state = "idle",
  last_activity = NOW - 1800000,
  parent_session = "/sessions/parent.jsonl",
}

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

local r1c = board.render({ idle_row, child_row }, { now_ms = NOW, cwd = "/p" })
check("t1 child row hidden by default", line_index(r1c.lines, "child-agent") == nil)
check("t1 hidden child excluded from section count", line_index(r1c.lines, "IDLE  1") ~= nil)
local r1cs = board.render(
  { idle_row, child_row },
  { now_ms = NOW, cwd = "/p", show_subagents = true }
)
check("t1 show_subagents reveals child row", line_index(r1cs.lines, "child-agent") ~= nil)
check("t1 shown child included in section count", line_index(r1cs.lines, "IDLE  2") ~= nil)

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

local r7s = board.render({ child_row }, { now_ms = NOW, cwd = "/d" })
check("t7 all-subagents hidden -> empty", line_index(r7s.lines, "No agents in this directory.") ~= nil)
check("t7 subagent hint mentions N", line_index(r7s.lines, "1 subagent hidden") ~= nil)
check("t7 subagent hint mentions S", line_index(r7s.lines, "press S to show") ~= nil)

local r7ac = board.render({ archived_child_row }, { now_ms = NOW, cwd = "/d" })
check(
  "t7 archived subagent names both required toggles",
  line_index(r7ac.lines, "1 archived subagent hidden \u{2014} press A and S to show") ~= nil
)
check("t7 archived subagent does not promise A alone", line_index(r7ac.lines, "archived \u{2014} press A to show") == nil)
check("t7 archived subagent does not promise S alone", line_index(r7ac.lines, "subagent hidden \u{2014} press S to show") == nil)

local r7ac_a = board.render(
  { archived_child_row },
  { now_ms = NOW, cwd = "/d", show_archived = true }
)
check("t7 archived shown still needs S", line_index(r7ac_a.lines, "press S to show") ~= nil)
local r7ac_s = board.render(
  { archived_child_row },
  { now_ms = NOW, cwd = "/d", show_subagents = true }
)
check("t7 subagents shown still needs A", line_index(r7ac_s.lines, "press A to show") ~= nil)
local r7ac_both = board.render(
  { archived_child_row },
  { now_ms = NOW, cwd = "/d", show_archived = true, show_subagents = true }
)
check("t7 both toggles reveal archived subagent", line_index(r7ac_both.lines, "archived-child-agent") ~= nil)

-- Test 8: key-legend footer
local r8 = board.render({ live_row, idle_row }, { now_ms = NOW, cwd = "/p" })
local lines8 = r8.lines
check("t8 legend line1 CR open present", line_index(lines8, "<CR> open") ~= nil)
check("t8 legend line2 d done present", line_index(lines8, "d done") ~= nil)
check("t8 legend line2 x archive present", line_index(lines8, "x archive") ~= nil)
check("t8 legend line2 A archived present", line_index(lines8, "A archived") ~= nil)
check("t8 legend line2 S subagents present", line_index(lines8, "S subagents") ~= nil)
local ddone_idx = line_index(lines8, "d done")
check("t8 legend d-done line inert (no line_to_row entry)", ddone_idx ~= nil and r8.line_to_row[ddone_idx] == nil)
local ddone_hl = ddone_idx and hl_for(r8.highlights, ddone_idx - 1, "AgentFleetTime") or nil
check("t8 legend d-done line has AgentFleetTime highlight", ddone_hl ~= nil)
check("t8 prompt-mode legend says i prompt (default)", line_index(lines8, "i prompt") ~= nil)

-- Test 8b: legend + empty-board hint reflect launch_input mode
local r8n = board.render({ live_row }, { now_ms = NOW, cwd = "/p", launch_input = "name" })
check("t8b name-mode legend says i name", line_index(r8n.lines, "i name") ~= nil)
check("t8b name-mode legend drops i prompt", line_index(r8n.lines, "i prompt") == nil)

local r7n = board.render({}, { now_ms = NOW, cwd = "/p", launch_input = "name" })
check("t8b name-mode empty hint says with a name", line_index(r7n.lines, "to launch with a name") ~= nil)
check("t8b name-mode empty hint drops prompt", line_index(r7n.lines, "to launch with a prompt") == nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
