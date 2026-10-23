vim.opt.runtimepath:append(vim.fn.getcwd())

local config = require("agent-fleet.config")
local board = require("agent-fleet.board")
local roster = require("agent-fleet.roster")
local actions = require("agent-fleet.actions")
local ui = require("agent-fleet.ui")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
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

local function find_row(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id then
      return row
    end
  end
  return nil
end

local TMP = vim.fn.tempname()
vim.fn.mkdir(TMP, "p")
local C = TMP .. "/proj"
vim.fn.mkdir(C, "p")
vim.fn.chdir(C)

config.setup({ agents = { vibe = { sessions_dir = TMP } } })

local id_open = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
local id_disk_arch = "b0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
local id_disk_rostered = "d0dddddd-dddd-4ddd-8ddd-dddddddddddd"
local id_roster_arch = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

write_vibe_meta(TMP, id_open, {
  cwd = C,
  title = "Open vibe work",
  start = "2026-11-01T10:00:00+00:00",
  bump = "2026-11-01T10:05:00+00:00",
})
write_vibe_meta(TMP, id_disk_arch, {
  cwd = C,
  title = "Vibe archived work",
  start = "2026-11-01T09:00:00+00:00",
  bump = "2026-11-01T09:05:00+00:00",
  endt = "2026-11-01T09:05:30+00:00",
  arch = '"2026-11-02T09:00:00+00:00"',
})
write_vibe_meta(TMP, id_disk_rostered, {
  cwd = C,
  title = "Rostered vibe work",
  start = "2026-11-01T08:00:00+00:00",
  bump = "2026-11-01T08:05:00+00:00",
  endt = "2026-11-01T08:05:30+00:00",
  arch = '"2026-11-02T08:00:00+00:00"',
})

roster.add({ id = id_disk_rostered, type = "vibe", name = "Rostered vibe work", cwd = C, created_at = 300 })
roster.add({ id = id_roster_arch, type = "vibe", name = "Roster archive work", cwd = C, created_at = 400 })
roster.set_archived(id_roster_arch, true)

local res_disk = actions.archive({
  id = id_disk_arch,
  name = "Vibe archived work",
  cwd = C,
  type = "vibe",
  archived = true,
})
check("archive reports vibe for pure disk-archived row", res_disk == "vibe")
check("archive on pure disk-archived row leaves roster empty", roster.get(id_disk_arch) == nil)
local row_disk = find_row(board.rows({ cwd = C, include_archived = true }), id_disk_arch)
check("pure disk-archived row stays archived after x", row_disk ~= nil and row_disk.archived == true)

local res_mixed = actions.archive({
  id = id_disk_rostered,
  name = "Rostered vibe work",
  cwd = C,
  type = "vibe",
  archived = true,
})
check("archive reports vibe for disk-archived row with unarchived roster entry", res_mixed == "vibe")
check(
  "archive leaves roster flag alone on disk-archived row with unarchived roster entry",
  roster.get(id_disk_rostered) ~= nil and roster.get(id_disk_rostered).archived == false
)

local res_roster = actions.archive({
  id = id_roster_arch,
  name = "Roster archive work",
  cwd = C,
  type = "vibe",
  archived = true,
})
check("archive still unarchives a roster-archived row", res_roster == false)
check(
  "archive on roster-archived row clears the roster flag",
  roster.get(id_roster_arch) ~= nil and roster.get(id_roster_arch).archived == false
)

roster.set_archived(id_roster_arch, true)

ui.open()
local bufnr = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()

local function keymap_callbacks(mode)
  local map = {}
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode or "n")) do
    map[km.lhs] = km.callback
  end
  return map
end

local function buf_lines()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function line_with(name)
  for i, l in ipairs(buf_lines()) do
    if l:find(name, 1, true) then
      return i
    end
  end
  return nil
end

local function cursor_to(name)
  local ln = line_with(name)
  vim.api.nvim_win_set_cursor(win, { ln, 0 })
  return ln
end

local cb = keymap_callbacks()
cb["X"]()
check("archived rows revealed", line_with("Vibe archived work") ~= nil)

local notified = {}
local orig_notify = vim.notify
local function capture_notify()
  notified = {}
  vim.notify = function(msg, level)
    notified[#notified + 1] = { msg = msg, level = level }
  end
end
local function restore_notify()
  vim.notify = orig_notify
end

capture_notify()
cursor_to("Vibe archived work")
cb["x"]()
restore_notify()

check("x on vibe-archived row notifies once", #notified == 1)
check(
  "x on vibe-archived row notifies vibe ownership",
  #notified == 1
    and notified[1].msg == "agent-fleet: archived by vibe \u{2014} unarchive from the vibe CLI \u{2014} Vibe archived work"
)
check(
  "x on vibe-archived row does not claim unarchived",
  notified[1] == nil or notified[1].msg ~= "agent-fleet: unarchived \u{2014} Vibe archived work"
)
check("x on vibe-archived row leaves roster empty", roster.get(id_disk_arch) == nil)
check("x on vibe-archived row keeps the row listed", line_with("Vibe archived work") ~= nil)
local row_post = find_row(board.rows({ cwd = C, include_archived = true }), id_disk_arch)
check("x on vibe-archived row leaves it archived on disk", row_post ~= nil and row_post.archived == true)

capture_notify()
local ln_arch = cursor_to("Vibe archived work")
ui.archive_range(ln_arch, ln_arch)
restore_notify()
check(
  "range x on vibe-archived row notifies vibe ownership",
  #notified == 1
    and notified[1].msg == "agent-fleet: archived by vibe \u{2014} unarchive from the vibe CLI \u{2014} Vibe archived work"
)
check("range x on vibe-archived row leaves roster empty", roster.get(id_disk_arch) == nil)

capture_notify()
cursor_to("Roster archive work")
cb["x"]()
restore_notify()
check(
  "x on roster-archived row still notifies unarchived",
  #notified == 1 and notified[1].msg == "agent-fleet: unarchived \u{2014} Roster archive work"
)
check(
  "x on roster-archived row still clears the roster flag",
  roster.get(id_roster_arch) ~= nil and roster.get(id_roster_arch).archived == false
)
check("x on roster-archived row keeps it on the board", line_with("Roster archive work") ~= nil)

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
