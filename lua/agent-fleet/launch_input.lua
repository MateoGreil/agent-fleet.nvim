local M = {}

local function name_mode()
  return require("agent-fleet.config").get().launch_input == "name"
end

local function pick(on_choice)
  local cfg = require("agent-fleet.config").get()
  local default_key = cfg.default_agent
  local items = {}
  local seen = {}

  if default_key and cfg.agents[default_key] then
    items[#items + 1] = default_key
    seen[default_key] = true
  end

  local rest = {}
  for key in pairs(cfg.agents) do
    if not seen[key] then
      table.insert(rest, key)
    end
  end
  table.sort(rest)

  for _, key in ipairs(rest) do
    items[#items + 1] = key
  end

  vim.ui.select(items, {
    prompt = "Launch agent: ",
    format_item = function(key)
      if key == default_key then
        return key .. " (default)"
      else
        return key
      end
    end,
  }, on_choice)
end

local function interactive_launch(field, prompt, agent_key)
  vim.ui.input({ prompt = prompt }, function(input)
    input = input and vim.trim(input)
    if input and input ~= "" then
      local opts = {}
      opts[field] = input
      if agent_key then
        opts.agent = agent_key
      end
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

function M.interactive_pick()
  pick(function(choice)
    if choice then
      if name_mode() then
        interactive_launch("name", "New agent name: ", choice)
      else
        interactive_launch("prompt", "New agent prompt: ", choice)
      end
    end
  end)
end

function M.pick_from_args(args)
  local value = vim.trim(args or "")
  if value == "" then
    return M.interactive_pick()
  end
  pick(function(choice)
    if choice then
      if name_mode() then
        require("agent-fleet").launch({ agent = choice, name = value })
      else
        require("agent-fleet").launch({ agent = choice, prompt = value })
      end
    end
  end)
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
