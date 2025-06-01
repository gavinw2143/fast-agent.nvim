-- plugin/fast_agent.lua
-- This file is auto‐sourced at startup by Neovim
-- We simply register user commands that call into lua/fast_agent.lua (“core”)

local fast = require("fast_agent")

--------------------------------------------------------------------------------
-- 1) FastAgentPrompt
--   - Exactly as before, but ensure the callback is stored so that _handle_submit
--     runs and we can auto‐enqueue the “user” message.
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgent", function(_)
	fast.open_prompt({
		title = "FastAgent ⇢ Type your prompt:",
		on_submit = function(input, convo_id)
			-- Notify immediately that we queued the request
			local msg = string.format(
				"[fast_agent.nvim] Prompt queued in conversation '%s'.", convo_id
			)
			vim.notify(msg, vim.log.levels.INFO)
			-- (Optionally) auto‐call get_response, so the user doesn’t need to run FastAgentFetch
			-- fast.get_response(convo_id, function(response_text)
			--   vim.notify("[fast_agent.nvim] Got response: " .. vim.inspect(response_text), vim.log.levels.INFO)
			-- end)
		end,
	})
end, {
	desc = "FastAgent: Open floating prompt",
})

--------------------------------------------------------------------------------
-- 2) FastAgentList
--   Instead of printing ASCII‐art tables, we pop up a vim.ui.select chooser.
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgentList", function(_)
	local convos = fast.list_conversations()
	if vim.tbl_isempty(convos) then
		vim.notify("[fast_agent.nvim] No conversations yet.", vim.log.levels.INFO)
		return
	end

	-- Build a list of formatted items (ID + Name + LastUpdated)
	local items = {}
	for _, c in ipairs(convos) do
		local when = os.date("%Y-%m-%d %H:%M", c.last_updated)
		table.insert(items, {
			display   = string.format("%-36s  %s  [%s]", c.id, c.name, when),
			id        = c.id,
			name      = c.name,
			timestamp = c.last_updated,
		})
	end

	-- Launch picker
	vim.ui.select(items, {
		prompt = "Select a conversation:",
		format_item = function(item) return item.display end,
	}, function(choice)
		if not choice then
			return
		end
		fast.set_current_conversation(choice.id)
		vim.notify(string.format(
			"[fast_agent.nvim] Switched to conversation → '%s' (%s)",
			choice.id, choice.name
		), vim.log.levels.INFO)
	end)
end, {
	nargs = 0,
	desc  = "FastAgent: List and choose a past conversation",
})

--------------------------------------------------------------------------------
-- 3) FastAgentSwitch
--   - Exactly the same logic, but we add “complete = …” so that <Tab> completes IDs
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgentSwitch", function(opts)
	local target = opts.args
	if target == "" then
		vim.notify("[fast_agent.nvim] Usage: :FastAgentSwitch <conversation_id>", vim.log.levels.WARN)
		return
	end
	fast.set_current_conversation(target)
end, {
	nargs    = 1,
	complete = function(arg_lead)
		local convos = fast.list_conversations()
		local matches = {}
		for _, c in ipairs(convos) do
			if vim.startswith(c.id, arg_lead) then
				table.insert(matches, c.id)
			end
		end
		return matches
	end,
	desc     = "FastAgent: Switch the current conversation by its ID",
})

--------------------------------------------------------------------------------
-- 4) FastAgentFetch
--   - Instead of opening a horizontal split, open a floating “chat bubble” window
--   - Make the buffer read‐only, set a filetype, and map <Esc> to close
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgentFetch", function(_)
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		vim.notify("[fast_agent.nvim] No active conversation. Use :FastAgentPrompt first.", vim.log.levels.ERROR)
		return
	end

	fast.get_response(c_id, function(response_text)
		vim.schedule(function()
			-- Create a scratch buffer
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, "FastAgentResponse")

			-- Determine floating window size
			local win_w = math.floor(vim.o.columns * 0.6)
			local win_h = math.floor(vim.o.lines * 0.6)
			local row   = math.floor((vim.o.lines - win_h) / 2)
			local col   = math.floor((vim.o.columns - win_w) / 2)

			-- Open the window
			local win   = vim.api.nvim_open_win(buf, true, {
				relative = "editor",
				width    = win_w,
				height   = win_h,
				row      = row,
				col      = col,
				style    = "minimal",
				border   = "rounded",
			})

			-- Set buffer options
			vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
			vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
			vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf }) -- let them get Markdown syntax

			-- Insert lines
			local lines = vim.split(response_text, "\n")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

			vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
			-- Map <Esc> to close this floating window
			vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<Cmd>bd!<CR>", { noremap = true, silent = true })

			vim.notify("[fast_agent.nvim] Assistant’s response displayed in floating window.", vim.log.levels.INFO)
		end)
	end)
end, {
	nargs = 0,
	desc  = "FastAgent: Fetch assistant response for the current conversation (in a float)",
})

--------------------------------------------------------------------------------
-- 5) FastAgentAppend
--   - Slight tweak: expand “~”, auto‐mkdir parent dir if needed, better errors
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgentAppend", function(opts)
	local path = opts.args
	if path == "" then
		vim.notify("[fast_agent.nvim] Usage: :FastAgentAppend <filepath>", vim.log.levels.WARN)
		return
	end
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		vim.notify("[fast_agent.nvim] No active conversation.", vim.log.levels.ERROR)
		return
	end

	-- Fetch the conversation from “core” state
	-- (We cannot guarantee fast.list_conversations() built a local cache, so we read from core's state.)
	local convo_data = fast._get_internal_state().conversations[c_id]
	if not convo_data then
		vim.notify("[fast_agent.nvim] Conversation not found locally.", vim.log.levels.ERROR)
		return
	end

	-- Find the last assistant message
	local msgs = convo_data.messages
	local assistant_msg = nil
	for i = #msgs, 1, -1 do
		if msgs[i].role == "assistant" then
			assistant_msg = msgs[i].content
			break
		end
	end
	if not assistant_msg then
		vim.notify("[fast_agent.nvim] No assistant message found in this conversation yet.", vim.log.levels.WARN)
		return
	end

	-- Delegate to core’s append_to_file() (which now expands “~” and mkdirs)
	fast.append_to_file(path, assistant_msg)
end, {
	nargs = 1,
	desc  = "FastAgent: Append latest assistant response of current conversation to <filepath>",
})

--------------------------------------------------------------------------------
-- 6) (Optional) FastAgentStatus – show current convo ID & name
--------------------------------------------------------------------------------
vim.api.nvim_create_user_command("FastAgentStatus", function(_)
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		vim.notify("[fast_agent.nvim] No active conversation.", vim.log.levels.INFO)
		return
	end
	local state = fast._get_internal_state() -- we’ll add _get_internal_state() below
	local info = state.conversations[c_id]
	if not info then
		vim.notify("[fast_agent.nvim] Current conversation missing from state.", vim.log.levels.ERROR)
		return
	end
	local when = os.date("%Y-%m-%d %H:%M", info.last_updated)
	vim.notify(
		string.format("Current convo: %s  (\"%s\")  [Last updated: %s]", c_id, info.name, when),
		vim.log.levels.INFO
	)
end, {
	nargs = 0,
	desc = "FastAgent: Show current conversation ID, name, and last‐updated timestamp",
})
