vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local board = require("agent-fleet.board")
local roster = require("agent-fleet.roster")
local agent = require("agent-fleet.agent")

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

-- Case 1: done_candidates returns only the plain (not done / not archived / not live) entry.
local C1 = "/proj/c1"
local id_plain = "11111111-1111-1111-1111-111111111111"
local id_done = "11111111-1111-1111-1111-111111111112"
local id_arch = "11111111-1111-1111-1111-111111111113"
local id_live = "11111111-1111-1111-1111-111111111114"
roster.add({ id = id_plain, type = "pi", name = "plain", cwd = C1 })
roster.add({ id = id_done, type = "pi", name = "done", cwd = C1 })
roster.mark_done(id_done)
roster.add({ id = id_arch, type = "pi", name = "arch", cwd = C1 })
roster.set_archived(id_arch, true)
roster.add({ id = id_live, type = "pi", name = "live", cwd = C1 })
local buf_live = vim.api.nvim_create_buf(false, true)
agent.agents["klive"] = { session_id = id_live, bufnr = buf_live, cwd = C1, name = "live" }

local dc = board.done_candidates(C1)
check("case1 plain present", has_id(dc, id_plain))
check("case1 done excluded", not has_id(dc, id_done))
check("case1 archived excluded", not has_id(dc, id_arch))
check("case1 live excluded", not has_id(dc, id_live))
check("case1 only one candidate", #dc == 1)

-- Case 2: archive_candidates returns both archived and non-archived for cwd, excludes other cwds.
local C2 = "/proj/c2"
local COther = "/proj/other"
local id_a = "22222222-2222-2222-2222-222222222221"
local id_b = "22222222-2222-2222-2222-222222222222"
local id_o = "22222222-2222-2222-2222-222222222223"
roster.add({ id = id_a, type = "pi", name = "a", cwd = C2 })
roster.add({ id = id_b, type = "pi", name = "b", cwd = C2 })
roster.set_archived(id_b, true)
roster.add({ id = id_o, type = "pi", name = "o", cwd = COther })
local ac = board.archive_candidates(C2)
check("case2 non-archived present", has_id(ac, id_a))
check("case2 archived present", has_id(ac, id_b))
check("case2 other cwd excluded", not has_id(ac, id_o))

-- Case 3: after mark_done, entry drops out of done_candidates.
local C3 = "/proj/c3"
local id3 = "33333333-3333-3333-3333-333333333333"
roster.add({ id = id3, type = "pi", name = "three", cwd = C3 })
check("case3 present before done", has_id(board.done_candidates(C3), id3))
roster.mark_done(id3)
check("case3 absent after done", not has_id(board.done_candidates(C3), id3))

-- Case 4: after set_archived true, entry drops out of done_candidates but stays
-- in archive_candidates (now flagged archived).
local C4 = "/proj/c4"
local id4 = "44444444-4444-4444-4444-444444444444"
roster.add({ id = id4, type = "pi", name = "four", cwd = C4 })
check("case4 present in done before archive", has_id(board.done_candidates(C4), id4))
roster.set_archived(id4, true)
check("case4 absent in done after archive", not has_id(board.done_candidates(C4), id4))
local e4 = find_id(board.archive_candidates(C4), id4)
check("case4 present in archive after archive", e4 ~= nil)
check("case4 flagged archived", e4 ~= nil and e4.archived == true)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
