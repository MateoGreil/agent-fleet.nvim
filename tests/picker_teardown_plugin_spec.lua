vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/agent-fleet.lua")

local af = require("agent-fleet")
local actions = require("agent-fleet.actions")
local agent = require("agent-fleet.agent")
local config = require("agent-fleet.config")
local roster = require("agent-fleet.roster")

local out = {}
local function check(name, cond)
  out[#out + 1] = (cond and "PASS " or "FAIL ") .. name
end

local cwd = vim.fn.tempname()
vim.fn.mkdir(cwd, "p")
vim.fn.chdir(cwd)
config.setup({ agents = { pi = { cmd = "true" } }, start_insert = false })

local entry_id = "aaaa1111-1111-4111-8111-111111111111"
roster.add({ id = entry_id, type = "pi", name = "demo", cwd = cwd })

local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(scratch)

local orig_mode = vim.api.nvim_get_mode
local orig_select = vim.ui.select
local orig_input = vim.ui.input
local orig_resume = af.resume
local orig_resume_session = agent.resume_session
local orig_rename = actions.rename

-- Picker stub: the confirm callback fires while the editor is still in
-- terminal mode; the teardown lands right after (fzf-lua's ui.select shape).
local function picker_in_teardown()
  vim.ui.select = function(items, _, on_choice)
    check("picker has candidates", items ~= nil and #items > 0 and items[1].id == entry_id)
    vim.api.nvim_get_mode = function()
      return { mode = "t" }
    end
    on_choice(items[1])
    vim.api.nvim_get_mode = function()
      return { mode = "n" }
    end
  end
end

local function picker_settled()
  vim.ui.select = function(items, _, on_choice)
    on_choice(items[1])
  end
end

-- AgentRename: picker -> input
actions.rename = function(target, name)
  return { id = target.id, name = name }
end
local rename_target, rename_name
local rename_mode
local function reset_rename()
  rename_target = nil
  rename_name = nil
  rename_mode = nil
  actions.rename = function(target, name)
    rename_target = target.id
    rename_name = name
    rename_mode = vim.api.nvim_get_mode().mode
    return true
  end
end

local input_mode
local function reset_input()
  vim.ui.input = function(_, on_confirm)
    input_mode = vim.api.nvim_get_mode().mode
    on_confirm("renamed-agent")
  end
end

-- AgentRename in terminal-mode teardown: input must wait for the settle
reset_rename()
reset_input()
picker_in_teardown()
vim.cmd("AgentRename")
check("AgentRename: input not opened while picker in terminal mode", rename_target == nil)
vim.wait(2000, function()
  return rename_target ~= nil
end, 10)
check("AgentRename: rename applied after teardown", rename_target == entry_id and rename_name == "renamed-agent")
check("AgentRename: input opened outside terminal mode", input_mode ~= "t" and input_mode ~= "nt")

-- AgentRename on a settled picker: synchronous behavior kept
reset_rename()
reset_input()
picker_settled()
vim.cmd("AgentRename")
check(
  "AgentRename settled: rename applied synchronously",
  rename_target == entry_id and rename_name == "renamed-agent"
)

-- AgentResume: picker -> resume
local resume_id, resume_mode
local function reset_resume()
  resume_id = nil
  resume_mode = nil
  af.resume = function(id)
    resume_id = id
    resume_mode = vim.api.nvim_get_mode().mode
    return nil
  end
end

reset_resume()
picker_in_teardown()
vim.cmd("AgentResume")
check("AgentResume: resume not run while picker in terminal mode", resume_id == nil)
vim.wait(2000, function()
  return resume_id ~= nil
end, 10)
check("AgentResume: resume ran after teardown", resume_id == entry_id)
check("AgentResume: resume ran outside terminal mode", resume_mode ~= "t" and resume_mode ~= "nt")

reset_resume()
picker_settled()
vim.cmd("AgentResume")
check("AgentResume settled: resume synchronous", resume_id == entry_id)

-- Agents (list & switch): picker -> resume_session
local session_spec, session_mode
local function reset_session()
  session_spec = nil
  session_mode = nil
  agent.resume_session = function(spec)
    session_spec = spec
    session_mode = vim.api.nvim_get_mode().mode
    return nil
  end
end

reset_session()
picker_in_teardown()
vim.cmd("Agents")
check("Agents: resume not run while picker in terminal mode", session_spec == nil)
vim.wait(2000, function()
  return session_spec ~= nil
end, 10)
check("Agents: resume ran after teardown", session_spec ~= nil and session_spec.id == entry_id)
check("Agents: resume ran outside terminal mode", session_mode ~= "t" and session_mode ~= "nt")

reset_session()
picker_settled()
vim.cmd("Agents")
check("Agents settled: resume synchronous", session_spec ~= nil and session_spec.id == entry_id)

vim.api.nvim_get_mode = orig_mode
vim.ui.select = orig_select
vim.ui.input = orig_input
af.resume = orig_resume
agent.resume_session = orig_resume_session
actions.rename = orig_rename

vim.fn.writefile(out, os.getenv("AGENT_FLEET_TEST_OUT"))
vim.cmd("qa!")
