vim.opt.runtimepath:append(vim.fn.getcwd())

local backends = require("agent-fleet.backends")
local config = require("agent-fleet.config")

config.setup({ agents = { pi = {} } })

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local pi_backend = backends.resolve("pi")
check("resolve pi has_disk true", pi_backend.has_disk == true)
check("resolve pi list callable", type(pi_backend.list) == "function")
check("resolve pi tail_info callable", type(pi_backend.tail_info) == "function")
check("resolve pi session_file callable", type(pi_backend.session_file) == "function")

local generic_backend = backends.resolve("generic")
check("resolve generic has_disk false", generic_backend.has_disk == false)
check("resolve generic list callable", type(generic_backend.list) == "function")
check("resolve generic tail_info callable", type(generic_backend.tail_info) == "function")

local missing_list = generic_backend.list("/any/cwd", "/any/dir")
check("generic list returns empty table", type(missing_list) == "table" and #missing_list == 0)

local missing_info = generic_backend.tail_info("/any/file")
check("generic tail_info returns nil", missing_info == nil)

local nonexistent_backend = backends.resolve("nonexistent")
check("nonexistent type resolves to generic", nonexistent_backend.has_disk == false)

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local slug = pi_backend.slug("/proj/test")
local dir = tmp .. "/" .. slug
vim.fn.mkdir(dir, "p")

local test_id = "12345678-1234-1234-1234-123456789abc"
local test_file = dir .. "/2026-01-01T00:00:00.000Z_" .. test_id .. ".jsonl"
vim.fn.writefile({ '{"id":"' .. test_id .. '"}' }, test_file)

local found = pi_backend.session_file("/proj/test", tmp, test_id)
check("session_file finds existing", found ~= nil and found == test_file)

local not_found = pi_backend.session_file("/proj/test", tmp, "99999999-9999-9999-9999-999999999999")
check("session_file returns nil for missing", not_found == nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
