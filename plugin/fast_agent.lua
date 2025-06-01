-- This is automatically sourced at startup.

-- Convenience alias
local fast = require("fast_agent")

local state = {
	last_input = ""
}

-- 1) Open a new floating prompt:
vim.api.nvim_create_user_command("FastAgentPrompt", function(_)
	fast.open_prompt({
		title = "FastAgent",
		on_submit = function(input, convo_id)
			-- For convenience, immediately queue up the API call in the background,
			-- then notify the user that the request was registered.
			local msg = string.format(
				"[fast_agent.nvim] Prompt queued in conversation '%s'.", convo_id
			)
			vim.notify(msg, vim.log.levels.INFO)
			-- Optionally: auto‐call get_response so the user doesn’t have to do it manually.
			--
			fast.get_response(convo_id, function(response_text)
				vim.notify("[fast_agent.nvim] Got response: " .. vim.inspect(response_text), vim.log.levels.INFO)
			end)
		end,
	})
end, { desc = "FastAgent: Open floating prompt" })

-- 2) List all conversations (in a pretty-printed table)
vim.api.nvim_create_user_command("FastAgentList", function(_)
	local convos = fast.list_conversations()
	if vim.tbl_isempty(convos) then
		print("[fast_agent.nvim] No conversations yet.")
		return
	end
	print("ID                                   │ Name            │ Last Updated")
	print("──────────────────────────────────────┼─────────────────┼───────────────")
	for _, c in ipairs(convos) do
		local date = os.date("%Y-%m-%d %H:%M", c.last_updated)
		print(string.format("%-36s │ %-15s │ %s", c.id, c.name, date))
	end
end, {
	nargs = 0,
	desc  = "FastAgent: List all past conversations",
})

-- 3) Switch the current conversation:
vim.api.nvim_create_user_command("FastAgentSwitch", function(opts)
	local target = opts.args
	if target == "" then
		print("[fast_agent.nvim] Usage: :FastAgentSwitch <conversation_id>")
		return
	end
	fast.set_current_conversation(target)
	print(string.format("[fast_agent.nvim] Switched current conversation → '%s'", target))
end, {
	nargs = 1,
	desc  = "FastAgent: Switch the current conversation by its ID",
})

-- 4) Fetch latest assistant response and echo it in a split
vim.api.nvim_create_user_command("FastAgentFetch", function(_)
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		print("[fast_agent.nvim] No active conversation. Use :FastAgentPrompt first.")
		return
	end
	fast.get_response(c_id, function(response_text)
		-- Once we have response_text, open a new scratch buffer and put it there
		vim.schedule(function()
			vim.cmd("new") -- open a horizontal split
			local buf = vim.api.nvim_get_current_buf()
			vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
			vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
			vim.api.nvim_buf_set_option(buf, "swapfile", false)
			vim.api.nvim_buf_set_name(buf, "FastAgentResponse")

			local lines = vim.split(response_text, "\n")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.api.nvim_buf_set_option(buf, "modifiable", false)
			print("[fast_agent.nvim] Inserted assistant response in new split.")
		end)
	end)
end, {
	nargs = 0,
	desc  = "FastAgent: Fetch assistant response for the current conversation and open it in a split",
})

-- 5) Append the latest assistant response to a file:
--    We look up the last message in the conversation (the assistant’s message).
vim.api.nvim_create_user_command("FastAgentAppend", function(opts)
	local path = opts.args
	if path == "" then
		print("[fast_agent.nvim] Usage: :FastAgentAppend <filepath>")
		return
	end
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		print("[fast_agent.nvim] No active conversation.")
		return
	end
	local convo = fast.list_conversations()
	-- Find the conversation
	local conv_data = state.conversations[c_id]
	if not conv_data then
		print("[fast_agent.nvim] Conversation not found locally.")
		return
	end
	-- Get the last assistant message in that convo
	local msgs = conv_data.messages
	local assistant_msg = nil
	for i = #msgs, 1, -1 do
		if msgs[i].role == "assistant" then
			assistant_msg = msgs[i].content
			break
		end
	end
	if not assistant_msg then
		print("[fast_agent.nvim] No assistant message found in this conversation yet.")
		return
	end
	fast.append_to_file(path, assistant_msg)
end, {
	nargs = 1,
	desc  = "FastAgent: Append latest assistant response of current conversation to <filepath>",
})
