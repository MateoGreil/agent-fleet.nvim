vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local r = require("agent-fleet.roster")
local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

check("empty load has 0 agents", #r.load().agents == 0)

r.add({ id = "aaa", type = "pi", name = "one", cwd = "/p1" })
check("get returns added", r.get("aaa") ~= nil and r.get("aaa").name == "one")
check(
  "defaults set",
  r.get("aaa").done == false
    and r.get("aaa").archived == false
    and type(r.get("aaa").created_at) == "number"
)

r.add({ id = "aaa", type = "pi", name = "one-renamed", cwd = "/p1" })
check("upsert replaces, no dup", #r.load().agents == 1 and r.get("aaa").name == "one-renamed")

r.add({ id = "bbb", type = "pi", name = "two", cwd = "/p2" })
r.set_archived("bbb", true)

check("list cwd /p1", #r.list({ cwd = "/p1" }) == 1)
check("list excludes archived by default", #r.list({}) == 1)
check("list include_archived", #r.list({ include_archived = true }) == 2)

r.add({ id = "ccc", type = "pi", name = "three", cwd = "/p1", created_at = 1 })
local sorted = r.list({})
check(
  "list sorted by created_at ascending",
  #sorted == 2 and sorted[1].id == "ccc" and sorted[2].id == "aaa"
)

r.mark_done("aaa")
check("mark_done", r.get("aaa").done == true)
r.set_name("aaa", "x")
check("set_name", r.get("aaa").name == "x")

check("set_name missing returns nil", r.set_name("nope", "y") == nil)
check("mark_done missing returns nil", r.mark_done("nope") == nil)
check("set_archived missing returns nil", r.set_archived("nope", true) == nil)

package.loaded["agent-fleet.roster"] = nil
local r2 = require("agent-fleet.roster")
check("persisted across reload", r2.get("aaa") ~= nil and r2.get("bbb") ~= nil)

local f = io.open(vim.fn.stdpath("data") .. "/agent-fleet/roster.json", "w")
f:write("{ not json")
f:close()
package.loaded["agent-fleet.roster"] = nil
check("corrupt file -> empty roster, no crash", #require("agent-fleet.roster").load().agents == 0)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
