vim.opt.runtimepath:append(vim.fn.getcwd())

local actions = require("agent-fleet.actions")
local roster = require("agent-fleet.roster")
local agent = require("agent-fleet.agent")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function make_term()
  vim.cmd("enew")
  vim.fn.jobstart({ "sleep", "300" }, { term = true })
  return vim.api.nvim_get_current_buf()
end

-- current_row: no vim.b.agent_fleet -> nil
local buf_none = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf_none)
check("current_row nil without agent_fleet", actions.current_row() == nil)

-- current_row: matching live agent -> populated row
local buf_live = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf_live)
vim.b.agent_fleet = { id = 7 }
agent.agents[7] = { session_id = "ID-A", bufnr = buf_live, cwd = "/proj/cr", name = "alpha" }
local row = actions.current_row()
check("current_row returns table", type(row) == "table")
check("current_row id is session_id", row ~= nil and row.id == "ID-A")
check("current_row live true", row ~= nil and row.live == true)
check("current_row bufnr matches", row ~= nil and row.bufnr == buf_live)
check("current_row name matches", row ~= nil and row.name == "alpha")
check("current_row cwd matches", row ~= nil and row.cwd == "/proj/cr")

-- current_row: live agent without session_id -> nil
local buf_noses = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf_noses)
vim.b.agent_fleet = { id = 8 }
agent.agents[8] = { session_id = nil, bufnr = buf_noses, cwd = "/proj/cr", name = "noses" }
check("current_row nil when session_id nil", actions.current_row() == nil)

-- close_live: live row wipes the terminal buffer and returns true
local buf_close = make_term()
local closed = actions.close_live({ live = true, bufnr = buf_close })
check("close_live returns true", closed == true)
check("close_live wipes buffer", vim.api.nvim_buf_is_valid(buf_close) == false)

-- close_live: non-live row is a no-op returning false
check("close_live false row returns false", actions.close_live({ live = false }) == false)

-- done: disk-only/unrostered live row -> rostered done + buffer wiped
local id_done = "dddddddd-dddd-dddd-dddd-dddddddddd01"
local buf_done = make_term()
check("done not rostered before", roster.get(id_done) == nil)
actions.done({ id = id_done, name = "doner", cwd = "/proj/d", live = true, bufnr = buf_done, archived = false })
check("done marks done", roster.get(id_done) ~= nil and roster.get(id_done).done == true)
check("done wipes live buffer", vim.api.nvim_buf_is_valid(buf_done) == false)

-- done: non-live row -> rostered done, no error
local id_done2 = "dddddddd-dddd-dddd-dddd-dddddddddd02"
actions.done({ id = id_done2, name = "doner2", cwd = "/proj/d", live = false })
check("done non-live marks done", roster.get(id_done2) ~= nil and roster.get(id_done2).done == true)

-- done: un-doing a live row -> returns false, not done, buffer kept
local id_undone = "dddddddd-dddd-dddd-dddd-dddddddddd03"
local buf_undone = make_term()
local res_undone =
  actions.done({ id = id_undone, name = "undoner", cwd = "/proj/d", live = true, bufnr = buf_undone, done = true })
check("done returns false when un-doing", res_undone == false)
check("undone clears done", roster.get(id_undone) ~= nil and roster.get(id_undone).done == false)
check("undone keeps buffer", vim.api.nvim_buf_is_valid(buf_undone) == true)

-- archive: live unarchived row -> returns true, archived, buffer wiped
local id_arch = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01"
local buf_arch = make_term()
local res = actions.archive({ id = id_arch, name = "arch", cwd = "/proj/a", live = true, bufnr = buf_arch, archived = false })
check("archive returns true when archiving", res == true)
check("archive sets archived", roster.get(id_arch) ~= nil and roster.get(id_arch).archived == true)
check("archive wipes buffer when archiving", vim.api.nvim_buf_is_valid(buf_arch) == false)

-- archive: un-archiving a live row -> returns false, not archived, buffer kept
local id_un = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02"
local buf_un = make_term()
local res2 = actions.archive({ id = id_un, name = "un", cwd = "/proj/a", live = true, bufnr = buf_un, archived = true })
check("archive returns false when unarchiving", res2 == false)
check("unarchive clears archived", roster.get(id_un) ~= nil and roster.get(id_un).archived == false)
check("unarchive keeps buffer", vim.api.nvim_buf_is_valid(buf_un) == true)

-- rename: not-yet-rostered live row -> rosters + updates live state, buffer var, buffer name
local id_ren = "rrrrrrrr-rrrr-rrrr-rrrr-rrrrrrrrrr01"
local buf_ren = make_term()
agent.agents[31] = { session_id = id_ren, bufnr = buf_ren, cwd = "/proj/r", name = "old" }
vim.b[buf_ren].agent_fleet = { id = 31 }
check("rename not rostered before", roster.get(id_ren) == nil)
actions.rename({ id = id_ren, name = "old", cwd = "/proj/r", live = true, bufnr = buf_ren }, "new name")
check("rename materializes roster with new name", roster.get(id_ren) ~= nil and roster.get(id_ren).name == "new name")
check("rename updates live agent name", agent.agents[31].name == "new name")
check("rename updates buffer var name", vim.b[buf_ren].agent_fleet ~= nil and vim.b[buf_ren].agent_fleet.name == "new name")
check("rename renames buffer", vim.endswith(vim.api.nvim_buf_get_name(buf_ren), "agent:new name"))

-- rename: dead (non-live) row -> roster name updated, no error
local id_ren2 = "rrrrrrrr-rrrr-rrrr-rrrr-rrrrrrrrrr02"
roster.add({ id = id_ren2, type = "pi", name = "old2", cwd = "/proj/r" })
actions.rename({ id = id_ren2, name = "old2", cwd = "/proj/r", live = false }, "new2")
check("rename dead row updates roster name", roster.get(id_ren2) ~= nil and roster.get(id_ren2).name == "new2")

-- rename: empty / nil new name is a no-op (no change, no error)
actions.rename({ id = id_ren, name = "new name", cwd = "/proj/r", live = true, bufnr = buf_ren }, "")
check("rename empty name no-op", roster.get(id_ren).name == "new name")
actions.rename({ id = id_ren, name = "new name", cwd = "/proj/r", live = true, bufnr = buf_ren }, nil)
check("rename nil name no-op", roster.get(id_ren).name == "new name")

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
