local M = {}

M.max_name_words = 5
M.max_name_chars = 100
M.max_default_chars = 40
M._warned_no_model = false

M.system_prompt =
  "You name coding-agent sessions. Given the task description below, reply with ONLY a short name of 2 to 5 words that describes the task. No quotes, no trailing punctuation, no explanation, no full sentence — just the name."

function M.sanitize(raw, max_words, max_chars)
  if raw == nil then
    return nil
  end

  local first
  for _, line in ipairs(vim.split(raw, "\n", { plain = true })) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      first = trimmed
      break
    end
  end
  if not first then
    return nil
  end

  for _, q in ipairs({ '"', "'", "`" }) do
    if #first >= 2 and first:sub(1, 1) == q and first:sub(-1) == q then
      first = vim.trim(first:sub(2, -2))
      break
    end
  end

  first = first:gsub("%s+", " ")

  if max_words and max_words > 0 then
    local words = vim.split(first, " ", { trimempty = true })
    if #words > max_words then
      local kept = {}
      for i = 1, max_words do
        kept[i] = words[i]
      end
      first = table.concat(kept, " ")
    end
  end

  if max_chars and max_chars > 0 and #first > max_chars then
    first = first:sub(1, max_chars):gsub("%s+$", "")
  end

  first = vim.trim(first)
  if first == "" then
    return nil
  end
  return first
end

function M.default_name(prompt)
  if type(prompt) ~= "string" then
    return nil
  end
  local first
  for _, line in ipairs(vim.split(prompt, "\n", { plain = true })) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      first = trimmed
      break
    end
  end
  if not first then
    return nil
  end
  first = first:gsub("%s+", " ")
  if vim.fn.strchars(first) > M.max_default_chars then
    first = vim.fn.strcharpart(first, 0, M.max_default_chars - 1) .. "\u{2026}"
  end
  return first
end

local namers = {
  pi = function(base_cmd, prompt, system, model, thinking)
    local argv = vim.split(base_cmd, " ", { trimempty = true })
    local extra = {
      "-p",
      prompt,
      "--system-prompt",
      system,
      "--model",
      model,
      "--thinking",
      thinking,
      "--no-tools",
      "--no-session",
      "--no-extensions",
      "--no-skills",
      "--no-context-files",
      "--no-prompt-templates",
      "--mode",
      "text",
    }
    for _, v in ipairs(extra) do
      argv[#argv + 1] = v
    end
    return argv
  end,
  claude = function(base_cmd, prompt, system, model, _thinking)
    local argv = vim.split(base_cmd, " ", { trimempty = true })
    local extra = {
      "-p",
      prompt,
      "--system-prompt",
      system,
      "--model",
      model,
      "--tools",
      "",
    }
    for _, v in ipairs(extra) do
      argv[#argv + 1] = v
    end
    return argv
  end,
}

function M.build_argv(backend, base_cmd, prompt, system, model, thinking)
  local builder = namers[backend]
  if not builder then
    return nil
  end
  return builder(base_cmd, prompt, system, model, thinking)
end

function M.eligible(agent, cfg)
  if not (cfg and cfg.auto_name and cfg.auto_name.enabled == true) then
    return false
  end
  if agent.auto_named ~= true then
    return false
  end
  if type(agent.session_id) ~= "string" then
    return false
  end
  if type(cfg.auto_name.model) ~= "string" or cfg.auto_name.model == "" then
    return false
  end
  local agent_cfg = cfg.agents and cfg.agents[agent.agent]
  if not agent_cfg then
    return false
  end
  local backend = agent_cfg.backend
  if not backend or not namers[backend] then
    return false
  end
  return true
end

function M.apply_name(session_id, raw)
  local name = M.sanitize(raw, M.max_name_words, M.max_name_chars)
  if not name then
    return
  end

  local entry = require("agent-fleet.roster").get(session_id)
  if not entry or entry.auto_named ~= true then
    return
  end

  local agent = require("agent-fleet.agent")
  local live
  for _, a in pairs(agent.agents) do
    if a.session_id == session_id then
      live = a
      break
    end
  end

  local row
  if live and live.bufnr and vim.api.nvim_buf_is_valid(live.bufnr) then
    row = { id = session_id, name = live.name, cwd = live.cwd, live = true, bufnr = live.bufnr }
  else
    row = { id = session_id, name = entry.name, cwd = entry.cwd, live = false }
  end

  require("agent-fleet.actions").rename(row, name, { auto = true })
  vim.notify("agent-fleet: auto-named \u{2014} " .. name, vim.log.levels.INFO)
end

function M.runner(argv, cwd, timeout_ms, cb)
  local done = false
  local function finish(result)
    if done then
      return
    end
    done = true
    cb(result)
  end

  local out = {}
  local timer
  local job = vim.fn.jobstart(argv, {
    cwd = cwd,
    stdin = "null",
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data or {}) do
        out[#out + 1] = l
      end
    end,
    on_exit = function(_, code)
      if timer then
        pcall(vim.fn.timer_stop, timer)
      end
      if code == 0 then
        finish(table.concat(out, "\n"))
      else
        finish(nil)
      end
    end,
  })

  if job <= 0 then
    finish(nil)
    return
  end

  timer = vim.fn.timer_start(timeout_ms, function()
    pcall(vim.fn.jobstop, job)
    finish(nil)
  end)
end

function M.name_from_prompt(agent, prompt)
  local cfg = require("agent-fleet.config").get()

  if not M.eligible(agent, cfg) then
    local agent_cfg = cfg.agents and cfg.agents[agent.agent]
    local backend = agent_cfg and agent_cfg.backend
    if
      cfg.auto_name
      and cfg.auto_name.enabled
      and agent.auto_named
      and agent.session_id
      and backend
      and namers[backend]
      and (type(cfg.auto_name.model) ~= "string" or cfg.auto_name.model == "")
      and not M._warned_no_model
    then
      M._warned_no_model = true
      vim.notify("agent-fleet: auto_name.enabled but no auto_name.model set", vim.log.levels.WARN)
    end
    return
  end

  if type(prompt) ~= "string" then
    return
  end
  prompt = vim.trim(prompt)
  if prompt == "" then
    return
  end
  local max_chars = cfg.auto_name.max_chars
  if max_chars and max_chars > 0 then
    prompt = string.sub(prompt, 1, max_chars)
  end

  local agent_cfg = cfg.agents[agent.agent]
  local backend = agent_cfg.backend
  local base_cmd = agent_cfg.cmd
  local argv = M.build_argv(backend, base_cmd, prompt, M.system_prompt, cfg.auto_name.model, cfg.auto_name.thinking)
  M.runner(argv, agent.cwd, cfg.auto_name.namer_timeout_ms, function(raw)
    if raw then
      M.apply_name(agent.session_id, raw)
    end
  end)
end

return M
