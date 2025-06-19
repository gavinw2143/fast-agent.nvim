local config  = require("fast_agent.config")
local state   = require("fast_agent.core.state")
local network = require("fast_agent.core.network")
local utils   = require("fast_agent.core.utils")
local keymaps = require("fast_agent.ui.keymaps")

local M = {}

function M.setup(opts)
  config.setup(opts)
  if config.get_user_config().use_default_keymaps then
    keymaps.install_default_keymaps()
  end
  state.ensure_cache_dir()
  state.load_state()
  require("fast_agent.ui.window").setup_ui(M)
end
M.get_user_config = config.get_user_config


M.create_new_conversation     = state.create_new_conversation
M.list_conversations          = state.list_conversations
M.set_current_conversation    = state.set_current_conversation
M.delete_conversation         = state.delete_conversation
M.get_current_conversation_id = state.get_current_conversation_id
M.get_state                   = state.get_state

M.send_text      = state.send_text
M.get_response   = network.get_response
M.append_to_file = utils.append_to_file

return M
