local M = {}

--- Build a `RELPATH:LINE` or `RELPATH:LINE1-LINE2` reference for a file,
--- relative to cwd when the file lives inside it, absolute otherwise.
--- @param path string|nil
--- @param cwd string
--- @param line1 integer
--- @param line2 integer
--- @return string|nil
function M.build_reference(path, cwd, line1, line2)
  if path == nil or path == "" then
    return nil
  end

  if line1 > line2 then
    line1, line2 = line2, line1
  end

  local abs_path = vim.fn.fnamemodify(path, ":p")
  local abs_cwd = vim.fn.fnamemodify(cwd, ":p")
  if abs_cwd:sub(-1) ~= "/" then
    abs_cwd = abs_cwd .. "/"
  end

  local relpath
  if abs_path:sub(1, #abs_cwd) == abs_cwd then
    relpath = abs_path:sub(#abs_cwd + 1)
  else
    relpath = abs_path
  end

  if line1 == line2 then
    return relpath .. ":" .. line1
  end
  return relpath .. ":" .. line1 .. "-" .. line2
end

--- @return table[] agents whose bufnr is a valid buffer
function M.live_agents()
  local agent = require("agent-fleet.agent")
  local out = {}
  for _, a in pairs(agent.agents) do
    if vim.api.nvim_buf_is_valid(a.bufnr) then
      out[#out + 1] = a
    end
  end
  return out
end

--- @return table|nil, table[]|nil resolved agent, or nil plus candidates
function M.resolve_target()
  local agent = require("agent-fleet.agent")

  if agent.last_focused_id then
    local a = agent.agents[agent.last_focused_id]
    if a and vim.api.nvim_buf_is_valid(a.bufnr) then
      return a, nil
    end
  end

  local live = M.live_agents()
  if #live == 1 then
    return live[1], nil
  end
  return nil, live
end

return M
