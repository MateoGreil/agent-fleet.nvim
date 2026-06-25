if vim.g.loaded_pi_fleet then
  return
end
vim.g.loaded_pi_fleet = true

vim.api.nvim_create_user_command("PiAgent", function(opts)
  require("pi-fleet").launch({ name = opts.args ~= "" and opts.args or nil })
end, {
  nargs = "?",
  desc = "pi-fleet: launch a pi agent in a terminal split",
})
