vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local board = require("agent-fleet.board")
local roster = require("agent-fleet.roster")
local sessions = require("agent-fleet.sessions")
local agent = require("agent-fleet.agent")

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

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
