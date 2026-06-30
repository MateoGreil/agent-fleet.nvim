vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")
local board = require("agent-fleet.board")
local pi_backend = require("agent-fleet.backends.pi")
local claude_backend = require("agent-fleet.backends.claude")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

config.setup({
  agents = {
    pi = { cmd = "true", sessions_dir = tmp },
    claude = { cmd = "true", sessions_dir = tmp },
  },
  default_agent = "pi",
})

local cwd = "/mixed/project"
local pi_slug = pi_backend.slug(cwd)
local claude_slug = claude_backend.slug(cwd)

local pi_dir = tmp .. "/" .. pi_slug
local claude_dir = tmp .. "/" .. claude_slug
vim.fn.mkdir(pi_dir, "p")
vim.fn.mkdir(claude_dir, "p")

local id_pi = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
local id_claude = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"

local pi_file = pi_dir .. "/2026-01-01T00:00:00.000Z_" .. id_pi .. ".jsonl"
local pi_header = string.format(
  '{"type":"session","version":3,"id":"%s","timestamp":"2026-01-01T00:00:00.000Z","cwd":"%s"}',
  id_pi,
  cwd
)
vim.fn.writefile({ pi_header }, pi_file)

local claude_file = claude_dir .. "/" .. id_claude .. ".jsonl"
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}' }, claude_file)

local rows = board.rows({ cwd = cwd, sessions_dir = tmp, include_archived = true })

local found_pi = false
local found_claude = false
for _, row in ipairs(rows) do
  if row.id == id_pi then
    check("mixed board pi row type", row.type == "pi")
    found_pi = true
  elseif row.id == id_claude then
    check("mixed board claude row type", row.type == "claude")
    found_claude = true
  end
end

check("mixed board found pi row", found_pi)
check("mixed board found claude row", found_claude)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
