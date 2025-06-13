local config = require("fast_agent.config")
local state = require("fast_agent.state")
local network = require("fast_agent.network")
local utils = require("fast_agent.utils")
local prompt = require("fast_agent.prompt")
local keymaps = require("fast_agent.keymaps")

local M = {}

M.setup = config.setup
M.get_user_config = config.get_user_config

M.create_new_conversation = state.create_new_conversation
M.list_conversations = state.list_conversations
M.set_current_conversation = state.set_current_conversation
M.delete_conversation = state.delete_conversation
M.get_current_conversation_id = state.get_current_conversation_id
M.get_internal_state = state.get_internal_state

M.send_text = state.send_text
M.get_response = network.get_response
M.append_to_file = utils.append_to_file

M.open_prompt = prompt.open_prompt
M._handle_submit = prompt._handle_submit

M._install_default_keymaps = keymaps.install_default_keymaps

return M