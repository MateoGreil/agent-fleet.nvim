vim.opt.runtimepath:append("/home/mat/agent-fleet.nvim")

local sessions = require("agent-fleet.sessions")
local util = require("agent-fleet.util")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function header(id, ts)
  return vim.json.encode({
    type = "session",
    version = 3,
    id = id,
    timestamp = ts,
    cwd = "/proj/x",
  })
end

local function msg(ts, role, stop_reason)
  local m = { role = role }
  if stop_reason then
    m.stopReason = stop_reason
  end
  return vim.json.encode({ type = "message", timestamp = ts, message = m })
end

local function event(kind, ts)
  return vim.json.encode({ type = kind, timestamp = ts })
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local counter = 0
local function write_fixture(lines)
  counter = counter + 1
  local f = tmp .. "/fix_" .. counter .. ".jsonl"
  vim.fn.writefile(lines, f)
  return f
end

local oracle_dir = vim.fn.tempname()
vim.fn.mkdir(oracle_dir, "p")
local slug_dir = oracle_dir .. "/" .. sessions.cwd_slug("/proj/x")
vim.fn.mkdir(slug_dir, "p")
local ms_counter = 0
local function ms_for(ts)
  ms_counter = ms_counter + 1
  local id = string.format("%08d-0000-0000-0000-000000000000", ms_counter)
  local f = slug_dir .. "/" .. ts .. "_" .. id .. ".jsonl"
  vim.fn.writefile({ header(id, ts) }, f)
  local list = sessions.list("/proj/x", oracle_dir)
  for _, e in ipairs(list) do
    if e.id == id then
      return e.created_at
    end
  end
  return nil
end

local stop_ts = "2026-01-01T00:00:00.000Z"
local f1 = write_fixture({ header("id1", "2025-12-31T00:00:00.000Z"), msg(stop_ts, "assistant", "stop") })
local i1 = sessions.tail_info(f1)
check("assistant/stop -> idle", i1 ~= nil and i1.state == "idle")
check("assistant/stop last_activity matches ts", i1 ~= nil and i1.last_activity == ms_for(stop_ts))
check("assistant/stop last_activity positive number", i1 ~= nil and type(i1.last_activity) == "number" and i1.last_activity > 0)

local f2 = write_fixture({ header("id2", "2026-01-01T00:00:00.000Z"), msg("2026-01-02T00:00:00.000Z", "user") })
local i2 = sessions.tail_info(f2)
check("user last -> working", i2 ~= nil and i2.state == "working")

local f3 = write_fixture({ header("id3", "2026-01-01T00:00:00.000Z"), msg("2026-01-02T00:00:00.000Z", "assistant", "toolUse") })
local i3 = sessions.tail_info(f3)
check("assistant/toolUse -> working", i3 ~= nil and i3.state == "working")

local f4 = write_fixture({ header("id4", "2026-01-01T00:00:00.000Z"), msg("2026-01-02T00:00:00.000Z", "assistant", "aborted") })
local i4 = sessions.tail_info(f4)
check("assistant/aborted -> stopped", i4 ~= nil and i4.state == "stopped")

local f5 = write_fixture({ header("id5", "2026-01-01T00:00:00.000Z"), msg("2026-01-02T00:00:00.000Z", "assistant", "error") })
local i5 = sessions.tail_info(f5)
check("assistant/error -> error", i5 ~= nil and i5.state == "error")

local stop_ts2 = "2026-02-01T00:00:00.000Z"
local mc_ts = "2026-02-01T00:05:00.000Z"
local f6 = write_fixture({
  header("id6", "2026-01-15T00:00:00.000Z"),
  msg(stop_ts2, "assistant", "stop"),
  event("model_change", mc_ts),
})
local i6 = sessions.tail_info(f6)
check("non-message after stop keeps state idle", i6 ~= nil and i6.state == "idle")
check("non-message last_activity == model_change ts", i6 ~= nil and i6.last_activity == ms_for(mc_ts))
check("non-message last_activity ~= stop ts", i6 ~= nil and i6.last_activity ~= ms_for(stop_ts2))

local hts = "2026-03-01T00:00:00.000Z"
local f7 = write_fixture({ header("id7", hts) })
local i7 = sessions.tail_info(f7)
check("header-only -> new", i7 ~= nil and i7.state == "new")
check("header-only last_activity == header ts", i7 ~= nil and i7.last_activity == ms_for(hts))

local i8 = sessions.tail_info(tmp .. "/does_not_exist.jsonl")
check("missing file -> nil", i8 == nil)
check("nil arg -> nil", sessions.tail_info(nil) == nil)

local big_final_ts = "2026-04-01T01:00:00.000Z"
local big = { header("idbig", "2026-04-01T00:00:00.000Z") }
for _ = 1, 3000 do
  big[#big + 1] = vim.json.encode({
    type = "thinking_level_change",
    timestamp = "2026-04-01T00:00:01.000Z",
    payload = string.rep("x", 20),
  })
end
big[#big + 1] = msg(big_final_ts, "assistant", "stop")
local fbig = write_fixture(big)
check("big file exceeds 16KB", vim.loop.fs_stat(fbig).size > 16384)
local i9 = sessions.tail_info(fbig)
check("big file tail -> idle", i9 ~= nil and i9.state == "idle")
check("big file last_activity == final ts", i9 ~= nil and i9.last_activity == ms_for(big_final_ts))

local now = 2000000000 * 1000
check("rel now", util.relative_time(now - 30 * 1000, now) == "now")
check("rel 5m", util.relative_time(now - 5 * 60 * 1000, now) == "5m")
check("rel 3h", util.relative_time(now - 3 * 3600 * 1000, now) == "3h")
check("rel 2d", util.relative_time(now - 2 * 86400 * 1000, now) == "2d")
check("rel 3w", util.relative_time(now - 3 * 604800 * 1000, now) == "3w")

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
