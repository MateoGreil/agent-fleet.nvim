vim.opt.runtimepath:append(vim.fn.getcwd())

local backends = require("agent-fleet.backends")
local config = require("agent-fleet.config")
local board = require("agent-fleet.board")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local claude = backends.resolve("claude")

check("slug /home/mat/agent-fleet.nvim", claude.slug("/home/mat/agent-fleet.nvim") == "-home-mat-agent-fleet-nvim")
check("slug /home/mat/.claude", claude.slug("/home/mat/.claude") == "-home-mat--claude")
check("slug /a/b+c_d", claude.slug("/a/b+c_d") == "-a-b-c-d")
check("slug colons and parens", claude.slug("/foo:bar(baz)") == "-foo-bar-baz-")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local cwd = "/test/project"
local slug = claude.slug(cwd)
local dir = tmp .. "/" .. slug
vim.fn.mkdir(dir, "p")

local uuid_a = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
local uuid_b = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
local file_a = dir .. "/" .. uuid_a .. ".jsonl"
local file_b = dir .. "/" .. uuid_b .. ".jsonl"

vim.fn.writefile({ '{"type":"user","message":{"role":"user"}}' }, file_a)
vim.fn.writefile({ '{"type":"user","message":{"role":"user"}}' }, file_b)

vim.loop.fs_utime(file_a, 1000000000, 1000000000)
vim.loop.fs_utime(file_b, 1000000001, 1000000001)

local list_result = claude.list(cwd, tmp)
check("list returns 2 entries", #list_result == 2)
check("list entry 1 id is uuid_a", list_result[1].id == uuid_a)
check("list entry 2 id is uuid_b", list_result[2].id == uuid_b)
check("list entry cwd matches scanned cwd", list_result[1].cwd == cwd)
check("list entry file is readable", vim.fn.filereadable(list_result[1].file) == 1)
check("list sorted by created_at ascending", list_result[1].created_at <= list_result[2].created_at)

local empty_list = claude.list("/other/project", tmp)
check("list missing dir returns empty table", type(empty_list) == "table" and #empty_list == 0)

local tool_use_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}' }, tool_use_file)
local info_tool_use = claude.tail_info(tool_use_file)
check("tool_use -> working", info_tool_use ~= nil and info_tool_use.state == "working")

local end_turn_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}' }, end_turn_file)
local info_end_turn = claude.tail_info(end_turn_file)
check("end_turn -> idle", info_end_turn ~= nil and info_end_turn.state == "idle")

local stop_sequence_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"stop_sequence"}}' }, stop_sequence_file)
local info_stop_sequence = claude.tail_info(stop_sequence_file)
check("stop_sequence -> idle", info_stop_sequence ~= nil and info_stop_sequence.state == "idle")

local max_tokens_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"max_tokens"}}' }, max_tokens_file)
local info_max_tokens = claude.tail_info(max_tokens_file)
check("max_tokens -> idle", info_max_tokens ~= nil and info_max_tokens.state == "idle")

local api_error_file = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},"isApiErrorMessage":true}',
}, api_error_file)
local info_api_error = claude.tail_info(api_error_file)
check("isApiErrorMessage -> error", info_api_error ~= nil and info_api_error.state == "error")

local api_status_file = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},"apiErrorStatus":500}',
}, api_status_file)
local info_api_status = claude.tail_info(api_status_file)
check("apiErrorStatus -> error", info_api_status ~= nil and info_api_status.state == "error")

local top_error_file = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},"error":{"message":"fail"}}',
}, top_error_file)
local info_top_error = claude.tail_info(top_error_file)
check("top-level error -> error", info_top_error ~= nil and info_top_error.state == "error")

local null_fields_file = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},"apiErrorStatus":null,"error":null}',
}, null_fields_file)
local info_null_fields = claude.tail_info(null_fields_file)
check("null error fields -> idle", info_null_fields ~= nil and info_null_fields.state == "idle")

local user_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"user","message":{"role":"user","content":"test"}}' }, user_file)
local info_user = claude.tail_info(user_file)
check("user message -> working", info_user ~= nil and info_user.state == "working")

local metadata_tail_file = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}',
  '{"type":"permission-mode","value":"always"}',
  '{"type":"pr-link","url":"https://github.com"}',
}, metadata_tail_file)
local info_metadata_tail = claude.tail_info(metadata_tail_file)
check("metadata tail preserves assistant state", info_metadata_tail ~= nil and info_metadata_tail.state == "idle")
check("metadata tail has last_activity mtime", info_metadata_tail ~= nil and type(info_metadata_tail.last_activity) == "number")

local mixed = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"permission-mode","value":"always"}',
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}',
  '{"type":"pr-link","url":"https://example.test"}',
}, mixed)
local info_mixed = claude.tail_info(mixed)
check("metadata around message: derives working from assistant", info_mixed ~= nil and info_mixed.state == "working")

local huge_line_file = vim.fn.tempname()
local huge_content = string.rep("X", 70000)
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},"padding":"' .. huge_content .. '"}',
  '{"type":"permission-mode","value":"always"}',
}, huge_line_file)
local info_huge_line = claude.tail_info(huge_line_file)
check("huge line crosses block boundary still found", info_huge_line ~= nil and info_huge_line.state == "idle")

local three_block = vim.fn.tempname()
vim.fn.writefile({
  '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"},"blob":"' .. string.rep("Z", 200000) .. '"}',
}, three_block)
local info_three = claude.tail_info(three_block)
check("200KiB line spanning 3 blocks: found and mapped", info_three ~= nil and info_three.state == "working")

local budget_file = vim.fn.tempname()
local lines = { '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}' }
for _ = 1, 20000 do
  lines[#lines + 1] = '{"type":"metadata","data":"' .. string.rep("Y", 60) .. '"}'
end
vim.fn.writefile(lines, budget_file)
local info_budget = claude.tail_info(budget_file)
check("budget exceeded -> unknown", info_budget ~= nil and info_budget.state == "unknown")

local info_nil = claude.tail_info(nil)
check("nil file -> nil", info_nil == nil)

local info_missing = claude.tail_info("/nonexistent/file.jsonl")
check("missing file -> nil", info_missing == nil)

local no_stopped_file = vim.fn.tempname()
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}' }, no_stopped_file)
local info_no_stopped = claude.tail_info(no_stopped_file)
check("never stopped state", info_no_stopped ~= nil and info_no_stopped.state ~= "stopped")

local session_found = claude.session_file(cwd, tmp, uuid_a)
check("session_file found", session_found ~= nil and session_found == file_a)

local session_missing = claude.session_file(cwd, tmp, "missing-id")
check("session_file missing", session_missing == nil)

local integration_tmp = vim.fn.tempname()
vim.fn.mkdir(integration_tmp, "p")
local integration_cwd = "/home/test/project"
local integration_slug = claude.slug(integration_cwd)
local integration_dir = integration_tmp .. "/" .. integration_slug
vim.fn.mkdir(integration_dir, "p")
local integration_id = "cccccccc-cccc-4ccc-cccc-cccccccccccc"
local integration_file = integration_dir .. "/" .. integration_id .. ".jsonl"
vim.fn.writefile({ '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}' }, integration_file)

config.setup({ agents = { claude = { cmd = "true", sessions_dir = integration_tmp } } })
local rows = board.rows({ cwd = integration_cwd })
local found_row = false
for _, row in ipairs(rows) do
  if row.id == integration_id then
    found_row = true
    check("integration row type is claude", row.type == "claude")
    check("integration row state not new", row.state ~= "new")
    check("integration row has numeric last_activity", type(row.last_activity) == "number")
    break
  end
end
check("integration found claude row", found_row)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
