local M = {}

M.system_prompt =
  "You name coding-agent sessions. Given the task description below, reply with ONLY a short name of 2 to 5 words that describes the task. No quotes, no trailing punctuation, no explanation, no full sentence — just the name."

local function extract_text(content)
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return nil
  end
  local parts = {}
  for _, block in ipairs(content) do
    if type(block) == "table" and type(block.text) == "string" then
      parts[#parts + 1] = block.text
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

function M.first_user_text(file, max_chars)
  if not file then
    return nil
  end
  local fd = io.open(file, "r")
  if not fd then
    return nil
  end

  local text
  for line in fd:lines() do
    local ok, entry = pcall(vim.json.decode, line)
    if
      ok
      and type(entry) == "table"
      and entry.type == "message"
      and type(entry.message) == "table"
      and entry.message.role == "user"
    then
      text = extract_text(entry.message.content)
      break
    end
  end
  fd:close()

  if type(text) ~= "string" then
    return nil
  end
  text = vim.trim(text)
  if text == "" then
    return nil
  end
  if max_chars and max_chars > 0 then
    text = string.sub(text, 1, max_chars)
  end
  return text
end

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

function M.build_argv(pi_cmd, prompt, system, model, thinking)
  local argv = vim.split(pi_cmd, " ", { trimempty = true })
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
end

return M
