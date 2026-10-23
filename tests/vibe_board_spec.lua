vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")
local board = require("agent-fleet.board")
local pi = require("agent-fleet.backends.pi")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local function find_row(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id then
      return row
    end
  end
  return nil
end

local function line_index(lines, needle)
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      return i
    end
  end
  return nil
end

local function utc_ms(y, mo, d, h, mi, s)
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  t = t - os.difftime(os.time(os.date("!*t", t)), t)
  return t * 1000
end

local function write_vibe_meta(root, id, opts)
  local dir = root .. "/unified/" .. id
  vim.fn.mkdir(dir, "p")
  local json = '{"session_id":"' .. id .. '"'
    .. ',"parent_session_id":' .. (opts.parent and ('"' .. opts.parent .. '"') or "null")
    .. ',"start_time":' .. (opts.start and ('"' .. opts.start .. '"') or "null")
    .. ',"end_time":' .. (opts.endt and ('"' .. opts.endt .. '"') or "null")
    .. ',"origin_directory":"' .. opts.cwd .. '"'
    .. ',"title":' .. (opts.title and ('"' .. opts.title .. '"') or "null")
    .. ',"bumped_at":' .. (opts.bump and ('"' .. opts.bump .. '"') or "null")
    .. ',"archived_at":' .. (opts.arch or "null")
    .. "}"
  vim.fn.writefile({ json }, dir .. "/meta.json")
  return dir .. "/meta.json"
end

config.setup({ agents = { pi = { cmd = "true" }, vibe = {} }, start_insert = false })

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")
local C = "/proj/vibe-arch"
local id_active = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
local id_archived = "b0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
local id_pi = "cccccccc-cccc-cccc-cccc-cccccccccccc"

write_vibe_meta(TMP, id_active, {
  cwd = C,
  title = "Active vibe work",
  start = "2026-11-01T10:00:00+00:00",
  bump = "2026-11-01T10:05:00+00:00",
})
write_vibe_meta(TMP, id_archived, {
  cwd = C,
  title = "Old vibe work",
  start = "2026-11-01T09:00:00+00:00",
  bump = "2026-11-01T09:05:00+00:00",
  endt = "2026-11-01T09:05:30+00:00",
  arch = '"2026-11-02T09:00:00+00:00"',
})

local pi_dir = TMP .. "/" .. pi.cwd_slug(C)
vim.fn.mkdir(pi_dir, "p")
vim.fn.writefile({
  string.format(
    '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}',
    id_pi,
    "2026-11-01T08:00:00.000Z",
    C
  ),
}, pi_dir .. "/2026-11-01T08:00:00.000Z_" .. id_pi .. ".jsonl")

local rows_default = board.rows({ cwd = C, sessions_dir = TMP })
check("vibe archived disk row excluded by default", find_row(rows_default, id_archived) == nil)
check("vibe unarchived disk row visible by default", find_row(rows_default, id_active) ~= nil)
check("pi disk row (nil archived field) visible by default", find_row(rows_default, id_pi) ~= nil)

local rows_incl = board.rows({ cwd = C, sessions_dir = TMP, include_archived = true })
local r_active = find_row(rows_incl, id_active)
local r_archived = find_row(rows_incl, id_archived)
local r_pi = find_row(rows_incl, id_pi)
check("vibe archived disk row included on demand", r_archived ~= nil)
check("vibe archived disk row flagged archived", r_archived ~= nil and r_archived.archived == true)
check("vibe unarchived row archived flag false", r_active ~= nil and r_active.archived == false)
check("pi row archived flag false", r_pi ~= nil and r_pi.archived == false)
check(
  "archived disk row sorts last",
  #rows_incl == 3 and rows_incl[3].id == id_archived
)

local rendered = board.render(rows_incl, {
  cwd = C,
  now_ms = utc_ms(2026, 11, 2, 10, 0, 0),
  show_archived = true,
})
local arch_header = line_index(rendered.lines, "ARCHIVED  1")
local arch_line = line_index(rendered.lines, "Old vibe work")
check(
  "vibe archived disk row lands in ARCHIVED section",
  arch_header ~= nil and arch_line ~= nil and arch_line > arch_header
)
check("unarchived rows stay grouped in IDLE", line_index(rendered.lines, "IDLE  2") ~= nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
