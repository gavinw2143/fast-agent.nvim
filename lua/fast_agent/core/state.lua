local Path = require("plenary.path")
local config = require("fast_agent.config")
local uv = vim.loop
local utils = require("fast_agent.core.utils")

local M = {}

local state = {
  conversations = {},
  current = nil,
  last_input = "",
}

local function state_json_path()
  local cfg = config.get_user_config()
  return Path:new(cfg.cache_dir, cfg.json_file):absolute()
end

function M.ensure_cache_dir()
  local cfg = config.get_user_config()
  local p = Path:new(cfg.cache_dir)
  if not p:exists() then
    p:mkdir({ parents = true })
  end
end

function M.save_state()
  M.ensure_cache_dir()
  local all = {
    conversations = state.conversations,
    current = state.current,
  }
  local encoded = vim.fn.json_encode(all)
  Path:new(state_json_path()):write(encoded, "w")
end

function M.load_state()
  local p = Path:new(state_json_path())
  if p:exists() then
    local content = p:read()
    local ok, tbl = pcall(vim.fn.json_decode, content)
    if ok and type(tbl) == "table" then
      state.conversations = tbl.conversations or {}
      state.current = tbl.current
    end
  end
end

function M.create_new_conversation()
  local c_id = utils.generate_id()
  local timestamp = os.time()
  state.conversations[c_id] = {
    name = "Conversation " .. tostring(#vim.tbl_keys(state.conversations) + 1),
    messages = {},
    cwd = uv.cwd(),
    last_updated = timestamp,
  }
  state.current = c_id
  M.save_state()
  return c_id
end

function M.list_conversations()
  local out = {}
  for id, info in pairs(state.conversations) do
    table.insert(out, { id = id, name = info.name, last_updated = info.last_updated })
  end
  table.sort(out, function(a, b) return a.last_updated > b.last_updated end)
  return out
end

function M.set_current_conversation(c_id)
  if not state.conversations[c_id] then
    vim.notify(string.format("[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id), vim.log.levels.ERROR)
    return
  end
  state.current = c_id
  M.save_state()
end

function M.delete_conversation(c_id)
  if not state.conversations[c_id] then
    vim.notify(string.format("[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id), vim.log.levels.ERROR)
    return
  end
  state.conversations[c_id] = nil
  state.current = nil
  M.save_state()
end

function M.get_current_conversation_id()
  return state.current
end

function M.get_state()
  return { conversations = state.conversations, current = state.current, last_input = state.last_input }
end

function M.send_text(text, opts)
  opts = opts or {}
  local c_id = opts.conversation or state.current
  if not c_id or not state.conversations[c_id] then
    c_id = M.create_new_conversation()
  end
  table.insert(state.conversations[c_id].messages, { role = "user", content = text })
  state.conversations[c_id].last_updated = os.time()
  M.save_state()
  return c_id
end

return M