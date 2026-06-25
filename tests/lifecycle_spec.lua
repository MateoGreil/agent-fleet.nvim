vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local board = require("agent-fleet.board")
local roster = require("agent-fleet.roster")
local sessions = require("agent-fleet.sessions")
local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")
config.setup({ sessions_dir = TMP })

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function has_id(list, id)
  for _, e in ipairs(list) do
    if e.id == id then
      return true
    end
  end
  return false
end

local function find_id(list, id)
  for _, e in ipairs(list) do
    if e.id == id then
      return e
    end
  end
  return nil
end

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

-- Case 1: done_candidates includes a live agent and a disk-only (non-roster)
-- session; excludes a done one and an archived one.
local C1 = "/proj/c1"
local id_plain = "11111111-1111-1111-1111-111111111111"
local id_done = "11111111-1111-1111-1111-111111111112"
local id_arch = "11111111-1111-1111-1111-111111111113"
local id_live = "11111111-1111-1111-1111-111111111114"
local id_disk = "11111111-1111-1111-1111-111111111115"
roster.add({ id = id_plain, type = "pi", name = "plain", cwd = C1 })
roster.add({ id = id_done, type = "pi", name = "done", cwd = C1 })
roster.mark_done(id_done)
roster.add({ id = id_arch, type = "pi", name = "arch", cwd = C1 })
roster.set_archived(id_arch, true)
roster.add({ id = id_live, type = "pi", name = "live", cwd = C1 })
local buf_live = vim.api.nvim_create_buf(false, true)
agent.agents["klive"] = { session_id = id_live, bufnr = buf_live, cwd = C1, name = "live" }
write_session(C1, id_disk, "2026-01-01T00:00:00.000Z")

local dc = board.done_candidates(C1)
check("case1 plain present", has_id(dc, id_plain))
check("case1 live included", has_id(dc, id_live))
check("case1 disk-only included", has_id(dc, id_disk))
check("case1 done excluded", not has_id(dc, id_done))
check("case1 archived excluded", not has_id(dc, id_arch))
check("case1 row shape", find_id(dc, id_live).live == true)

-- Case 2: archive_candidates returns archived + non-archived (incl. live and
-- disk-only) for cwd, excludes other cwds.
local C2 = "/proj/c2"
local COther = "/proj/other"
local id_a = "22222222-2222-2222-2222-222222222221"
local id_b = "22222222-2222-2222-2222-222222222222"
local id_o = "22222222-2222-2222-2222-222222222223"
local id_c2disk = "22222222-2222-2222-2222-222222222224"
local id_c2live = "22222222-2222-2222-2222-222222222225"
roster.add({ id = id_a, type = "pi", name = "a", cwd = C2 })
roster.add({ id = id_b, type = "pi", name = "b", cwd = C2 })
roster.set_archived(id_b, true)
roster.add({ id = id_o, type = "pi", name = "o", cwd = COther })
write_session(C2, id_c2disk, "2026-02-02T00:00:00.000Z")
local buf_c2 = vim.api.nvim_create_buf(false, true)
agent.agents["kc2"] = { session_id = id_c2live, bufnr = buf_c2, cwd = C2, name = "c2live" }
local ac = board.archive_candidates(C2)
check("case2 non-archived present", has_id(ac, id_a))
check("case2 archived present", has_id(ac, id_b))
check("case2 disk-only present", has_id(ac, id_c2disk))
check("case2 live present", has_id(ac, id_c2live))
check("case2 other cwd excluded", not has_id(ac, id_o))

-- Case 3: materialize-then-flag for a disk-only row not yet in the roster (done).
local C3 = "/proj/c3"
local id3 = "33333333-3333-3333-3333-333333333333"
write_session(C3, id3, "2026-03-03T00:00:00.000Z")
check("case3 not in roster before", roster.get(id3) == nil)
local row3 = find_id(board.done_candidates(C3), id3)
check("case3 disk-only is a done candidate", row3 ~= nil)
roster.ensure({ id = row3.id, type = "pi", name = row3.name, cwd = row3.cwd })
roster.mark_done(row3.id)
check("case3 entry materialized", roster.get(id3) ~= nil)
check("case3 marked done", roster.get(id3).done == true)
check("case3 drops out of done_candidates", not has_id(board.done_candidates(C3), id3))

-- Case 4: materialize-then-flag archive toggling a previously-untracked row.
local C4 = "/proj/c4"
local id4 = "44444444-4444-4444-4444-444444444444"
write_session(C4, id4, "2026-04-04T00:00:00.000Z")
check("case4 not in roster before", roster.get(id4) == nil)
local row4 = find_id(board.archive_candidates(C4), id4)
check("case4 disk-only is an archive candidate", row4 ~= nil)
roster.ensure({ id = row4.id, type = "pi", name = row4.name, cwd = row4.cwd })
roster.set_archived(row4.id, not row4.archived)
check("case4 entry materialized", roster.get(id4) ~= nil)
check("case4 flagged archived", roster.get(id4).archived == true)
local row4b = find_id(board.archive_candidates(C4), id4)
check("case4 still an archive candidate", row4b ~= nil and row4b.archived == true)
check("case4 absent from done_candidates", not has_id(board.done_candidates(C4), id4))

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
