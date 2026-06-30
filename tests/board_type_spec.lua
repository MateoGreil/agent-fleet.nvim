vim.opt.runtimepath:append(vim.fn.getcwd())

local board = require("agent-fleet.board")
local pi_backend = require("agent-fleet.backends.pi")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local cwd = "/proj/x"
local slug = pi_backend.slug(cwd)
local dir = tmp .. "/" .. slug
vim.fn.mkdir(dir, "p")

local test_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local test_file = dir .. "/2026-01-01T00:00:00.000Z_" .. test_id .. ".jsonl"
local header = string.format(
  '{"type":"session","version":3,"id":"%s","timestamp":"2026-01-01T00:00:00.000Z","cwd":"%s"}',
  test_id,
  cwd
)
vim.fn.writefile({ header }, test_file)

local rows = board.rows({ cwd = cwd, sessions_dir = tmp })
check("board finds disk session", #rows == 1)
check("disk row has type=pi", rows[1] and rows[1].type == "pi")
check("disk row has correct id", rows[1] and rows[1].id == test_id)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
