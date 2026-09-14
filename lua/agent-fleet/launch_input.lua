local M = {}

local function name_mode()
  return require("agent-fleet.config").get().launch_input == "name"
end

local function interactive_launch(field, prompt)
  vim.ui.input({ prompt = prompt }, function(input)
    input = input and vim.trim(input)
    if input and input ~= "" then
      local opts = {}
      opts[field] = input
      require("agent-fleet").launch(opts)
    end
  end)
end

function M.interactive()
  if name_mode() then
    interactive_launch("name", "New agent name: ")
  else
    interactive_launch("prompt", "New agent prompt: ")
  end
end

function M.from_args(args)
  local value = vim.trim(args or "")
  if value == "" then
    return M.interactive()
  end
  if name_mode() then
    require("agent-fleet").launch({ name = value })
  else
    require("agent-fleet").launch({ prompt = value })
  end
end

return M
