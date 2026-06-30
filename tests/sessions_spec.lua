vim.opt.runtimepath:append(vim.fn.getcwd())

local sessions = require("agent-fleet.backends.pi")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

check("slug /home/mat", sessions.cwd_slug("/home/mat") == "--home-mat--")
check(
  "slug chezmoi",
  sessions.cwd_slug("/home/mat/.local/share/chezmoi") == "--home-mat-.local-share-chezmoi--"
)
check(
  "slug agent-fleet",
  sessions.cwd_slug("/home/mat/agent-fleet.nvim") == "--home-mat-agent-fleet.nvim--"
)

local missing = vim.fn.tempname()
local r_missing = sessions.list("/proj/x", missing)
check("missing dir returns empty", type(r_missing) == "table" and #r_missing == 0)

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local dir = tmp .. "/" .. sessions.cwd_slug("/proj/x")
vim.fn.mkdir(dir, "p")

local function header(id, ts)
  return string.format(
    '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"/proj/x"}',
    id,
    ts
  )
end

local id_early = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local id_late = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local f_early = dir .. "/2026-01-01T00:00:00.000Z_" .. id_early .. ".jsonl"
local f_late = dir .. "/2026-06-01T12:00:00.000Z_" .. id_late .. ".jsonl"
vim.fn.writefile({ header(id_early, "2026-01-01T00:00:00.000Z") }, f_early)
vim.fn.writefile({ header(id_late, "2026-06-01T12:00:00.000Z") }, f_late)

local r = sessions.list("/proj/x", tmp)
check("list returns 2", #r == 2)
check("sorted ascending id", r[1] and r[2] and r[1].id == id_early and r[2].id == id_late)
check(
  "created_at ascending",
  r[1] and r[2] and r[1].created_at < r[2].created_at
)
check("entry1 cwd", r[1] and r[1].cwd == "/proj/x")
check(
  "files exist",
  r[1] and r[2] and vim.fn.filereadable(r[1].file) == 1 and vim.fn.filereadable(r[2].file) == 1
)

local id_corrupt = "cccccccc-cccc-cccc-cccc-cccccccccccc"
local f_corrupt = dir .. "/2026-03-01T00:00:00.000Z_" .. id_corrupt .. ".jsonl"
vim.fn.writefile({ "this is not json {{{" }, f_corrupt)

local r2 = sessions.list("/proj/x", tmp)
check("corrupt file still listed", #r2 == 3)
check(
  "corrupt id from filename",
  (function()
    for _, e in ipairs(r2) do
      if e.id == id_corrupt then
        return true
      end
    end
    return false
  end)()
)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
