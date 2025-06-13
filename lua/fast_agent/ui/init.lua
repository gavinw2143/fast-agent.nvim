local home = require("fast_agent.ui.home")
local render = require("fast_agent.ui.render")
local actions = require("fast_agent.ui.actions")

local M = {}

M.toggle_home_panel = home.toggle_home_panel
M.refresh_conversation_list = render.refresh_conversation_list
M.refresh_message_history = render.refresh_message_history
M.select_conversation = actions.select_conversation
M.create_conversation = actions.create_conversation
M.delete_conversation = actions.delete_conversation
M.submit_prompt = actions.submit_prompt

return M