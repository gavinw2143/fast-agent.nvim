-- File: ~/.config/nvim/lua/fast_agent_ui.lua

local M = {}

-- Grab the “core” FastAgent module
local fast = require("fast_agent")

-- ----------------------------------------------------------------------------
-- Populate the “conversation list” buffer on the left
-- ----------------------------------------------------------------------------
local function refresh_conversation_list(bufnr)
	-- Fetch all conversations from our core state
	local convos = fast.list_conversations()
	local lines = {}

	if vim.tbl_isempty(convos) then
		lines = { "[No conversations yet]" }
	else
		-- Each line: "<short-ID>  │ <NAME>  │ <YYYY-MM-DD HH:MM>"
		for _, c in ipairs(convos) do
			local short_id = c.id:sub(1, 8)
			local when = os.date("%Y-%m-%d %H:%M", c.last_updated)
			table.insert(lines, string.format("%-8s │ %-15s │ %s", short_id, c.name, when))
		end
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

-- ----------------------------------------------------------------------------
-- Populate the “message history” buffer (top-right) for the current conversation
-- ----------------------------------------------------------------------------
local function refresh_message_history(bufnr)
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No active conversation" })
		vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
		return
	end

	-- Retrieve the in-memory state from the core
	local state = fast._get_internal_state()
	local convo = state.conversations[c_id] or { messages = {} }

	local lines = {}
	for _, msg in ipairs(convo.messages) do
		local prefix = (msg.role == "user") and "> " or ":: "
		local content_lines = vim.split(msg.content, "\n")

		for i, cl in ipairs(content_lines) do
			if i == 1 then
				-- First sub‐line gets the prefix
				table.insert(lines, prefix .. cl)
			else
				-- Subsequent sub‐lines get padded with spaces to align under the prefix
				table.insert(lines, string.rep(" ", #prefix) .. cl)
			end
		end

		-- Blank line between messages
		table.insert(lines, "")
	end

	if #lines == 0 then
		lines = { "[Conversation is empty]" }
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

	-- Scroll to the bottom
	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { #lines, 0 })
	end
end

-- ----------------------------------------------------------------------------
-- Open the “FastAgent Home” tabpage
-- ----------------------------------------------------------------------------
function M.toggle_home_panel()
	-- If it already exists, close everything and clear state
	if M.win_convos and vim.api.nvim_win_is_valid(M.win_convos) then
		-- Close prompt first, then history, then convos
		if M.win_input and vim.api.nvim_win_is_valid(M.win_input) then
			vim.api.nvim_win_close(M.win_input, true)
		end
		if M.win_history and vim.api.nvim_win_is_valid(M.win_history) then
			vim.api.nvim_win_close(M.win_history, true)
		end
		if M.win_convos and vim.api.nvim_win_is_valid(M.win_convos) then
			vim.api.nvim_win_close(M.win_convos, true)
		end

		-- Clear stored handles
		M.win_convos = nil
		M.buf_convos = nil
		M.win_history = nil
		M.buf_history = nil
		M.win_input = nil
		M.buf_input = nil
		return
	end

	-- Otherwise, create three floating windows side by side/in a column split
	local cols       = vim.o.columns
	local lines      = vim.o.lines

	-- Dimensions:
	local conv_w     = math.floor(cols * 0.20)
	local right_w    = cols - conv_w
	local hist_h     = math.floor(lines * 0.80)
	local prompt_h   = lines - hist_h

	local buf_convos = vim.api.nvim_create_buf(false, true)
	if vim.fn.bufnr(buf_convos) == -1 then
		vim.api.nvim_buf_set_name(buf_convos, "FastAgentConvos")
	end
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_convos })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf_convos })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf_convos })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf_convos })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf_convos })

	local win_convos = vim.api.nvim_open_win(buf_convos, true, {
		relative = "editor",
		row      = math.floor(lines * 0.05),
		col      = math.floor(cols * 0.05),
		width    = math.floor(conv_w * 0.90),
		height   = math.floor(lines * 0.90),
		style    = "minimal",
		border   = "rounded",
	})

	-- Map <CR> in this buffer to switch conversation
	vim.api.nvim_buf_set_keymap(
		buf_convos, "n", "<CR>",
		[[<Cmd>lua require("fast_agent_ui")._select_conversation()<CR>]],
		{ noremap = true, silent = true }
	)
	-- Map `n` to "new conversation"
	vim.api.nvim_buf_set_keymap(
		buf_convos, "n", "n",
		[[<Cmd>lua require("fast_agent_ui")._create_conversation()<CR>]],
		{ noremap = true, silent = true }
	)
	-- Map `d` to “delete conversation under cursor”
	vim.api.nvim_buf_set_keymap(
		buf_convos, "n", "d",
		[[<Cmd>lua require("fast_agent_ui")._delete_conversation()<CR>]],
		{ noremap = true, silent = true }
	)

	local buf_history = vim.api.nvim_create_buf(false, true)
	if vim.fn.bufnr(buf_history) == -1 then
		vim.api.nvim_buf_set_name(buf_history, "FastAgentHistory")
	end
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_history })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf_history })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf_history })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf_history })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf_history })


	local win_history = vim.api.nvim_open_win(buf_history, false, {
		relative = "editor",
		row      = math.floor(lines * 0.05),
		col      = math.floor(conv_w * 1.05),
		width    = math.floor(right_w * 0.90),
		height   = math.floor(hist_h * 0.90),
		style    = "minimal",
		border   = "rounded",
	})

	local buf_input = vim.api.nvim_create_buf(false, true)
	if vim.fn.bufnr(buf_input) == -1 then
		vim.api.nvim_buf_set_name(buf_input, "FastAgentInput")
	end
	vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf_input })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf_input })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf_input })
	vim.fn.prompt_setprompt(buf_input, "> ")

	local win_input = vim.api.nvim_open_win(buf_input, false, {
		relative = "editor",
		row      = math.floor(hist_h * 1.05),
		col      = math.floor(conv_w * 1.05),
		width    = math.floor(right_w * 0.90),
		height   = math.floor(prompt_h * 0.90),
		style    = "minimal",
		border   = "rounded",
	})

	-- When <CR> is pressed in this prompt, send to FastAgent and refresh history
	vim.api.nvim_buf_set_keymap(
		buf_input, "i", "<CR>",
		[[<C-\><C-n><Cmd>lua require("fast_agent_ui")._submit_prompt()<CR>]],
		{ noremap = true, silent = true }
	)
	-- Map <Esc> in prompt to just clear it
	vim.api.nvim_buf_set_keymap(
		buf_input, "n", "<Esc>",
		[[<Cmd>lua vim.api.nvim_buf_set_option(0, "modifiable", true) |
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {}) |
      vim.api.nvim_buf_set_option(0, "modifiable", false) |
      vim.cmd("startinsert")<CR>]],
		{ noremap = true, silent = true }
	)

	-- Populate both convo list and history right away
	refresh_conversation_list(buf_convos)
	refresh_message_history(buf_history)

	-- Store handles so we know how to close them later
	M.win_convos  = win_convos
	M.buf_convos  = buf_convos
	M.win_history = win_history
	M.buf_history = buf_history
	M.win_input   = win_input
	M.buf_input   = buf_input

	-- Finally, put the cursor into the prompt buffer and start insert mode
	vim.api.nvim_set_current_win(win_input)
	vim.cmd("startinsert")
end

-- ----------------------------------------------------------------------------
-- Called when user presses <CR> in the “prompt” buffer
-- ----------------------------------------------------------------------------
function M._submit_prompt()
	-- Identify which buffer is the prompt and which is history
	local prompt_buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
	local input_text = table.concat(lines, "\n")

	if input_text == "" then
		vim.notify("[fast_agent.nvim] Please type something before submitting.", vim.log.levels.WARN)
		return
	end

	-- Send it into the core, creating a new conversation if needed
	local c_id = fast.send_text(input_text)

	-- As soon as we enqueue the user text, refresh the LEFT list (so timestamps update)
	local left_win = vim.fn.win_findbuf(vim.fn.bufnr("FastAgentConvos"))[1]
	if left_win then
		refresh_conversation_list(vim.api.nvim_win_get_buf(left_win))
	end

	-- Show a notification
	vim.notify(string.format("[fast_agent.nvim] Prompt queued in conversation '%s'.", c_id), vim.log.levels.INFO)

	-- Optionally: immediately fetch assistant’s response and update history
	fast.get_response(c_id, function(response_text)
		vim.schedule(function()
			-- Find the “history” buffer and refresh it
			local hist_buf = vim.fn.bufnr("FastAgentHistory")
			if hist_buf ~= -1 then
				refresh_message_history(hist_buf)
			end

			-- Also refresh the LEFT list again (last_updated changed)
			local buf_convos = vim.fn.bufnr("FastAgentConvos")
			if buf_convos ~= -1 then
				refresh_conversation_list(buf_convos)
			end
		end)
	end)

	vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, {}) -- clear every line

	local prompt_win = vim.fn.bufwinid(prompt_buf)
	if prompt_win ~= -1 then
		vim.api.nvim_set_current_win(prompt_win)
		vim.cmd("startinsert")
	end
end

-- ----------------------------------------------------------------------------
-- Called when user hits <CR> in the “conversation list” buffer
-- ----------------------------------------------------------------------------
function M._select_conversation()
	local buf_convos = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)[1] -- 1-based line number
	local line = vim.api.nvim_buf_get_lines(buf_convos, cursor_pos - 1, cursor_pos, false)[1]
	if not line or line:match("^%[No") then
		return
	end

	-- Extract the short ID field (first 8 chars of line)
	local short_id = line:sub(1, 8)
	-- Find the full ID in core’s state
	local state = fast._get_internal_state()
	for full_id, info in pairs(state.conversations) do
		if full_id:sub(1, 8) == short_id then
			fast.set_current_conversation(full_id)
			vim.notify(string.format("[fast_agent.nvim] Switched to convo '%s' (%s)", full_id, info.name), vim.log.levels.INFO)

			-- Refresh the history buffer
			local hist_buf = vim.fn.bufnr("FastAgentHistory")
			if hist_buf ~= -1 then
				refresh_message_history(hist_buf)
			end

			-- Also update timestamp in the list
			refresh_conversation_list(buf_convos)
			return
		end
	end
	vim.notify("[fast_agent.nvim] Could not find conversation for line: " .. line, vim.log.levels.ERROR)
end

-- ----------------------------------------------------------------------------
-- Create a new conversation (prompt for a name, then refresh)
-- ----------------------------------------------------------------------------
function M._create_conversation()
	-- Prompt the user for a conversation name
	vim.ui.input({ prompt = "New conversation name: " }, function(input)
		if not input or input:match("^%s*$") then
			vim.notify("[fast_agent.nvim] Aborted: no name given.", vim.log.levels.WARN)
			return
		end

		-- Assume `fast.create_conversation(name)` returns the new convo’s full ID.
		-- (If your core module uses a different API, adjust accordingly.)
		local c_id = fast.create_new_conversation()

		-- Immediately switch into that new conversation:
		fast.set_current_conversation(c_id)

		-- Refresh the left‐pane list and the right‐pane history:
		local buf_convos = vim.fn.bufnr("FastAgentConvos")
		if buf_convos ~= -1 then
			refresh_conversation_list(buf_convos)
		end

		local hist_buf = vim.fn.bufnr("FastAgentHistory")
		if hist_buf ~= -1 then
			refresh_message_history(hist_buf)
		end

		vim.notify(string.format(
			"[fast_agent.nvim] Created conversation “%s” (%s).",
			input, c_id
		), vim.log.levels.INFO)
	end)
end

-- ----------------------------------------------------------------------------
-- Delete the conversation under the cursor (with confirmation)
-- ----------------------------------------------------------------------------
function M._delete_conversation()
	local buf_convos = vim.api.nvim_get_current_buf()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf_convos, cursor_line - 1, cursor_line, false)[1]

	if not line or line:match("^%[No") then
		vim.notify("[fast_agent.nvim] No conversation here to delete.", vim.log.levels.WARN)
		return
	end

	-- Extract the 8-char “short ID” from the start of the line:
	local short_id = line:sub(1, 8)

	-- Look up the full ID in core’s in-memory state:
	local state = fast._get_internal_state()
	local full_id_to_delete = nil
	local name_to_delete = nil

	for full_id, info in pairs(state.conversations) do
		if full_id:sub(1, 8) == short_id then
			full_id_to_delete = full_id
			name_to_delete = info.name
			break
		end
	end

	if not full_id_to_delete then
		vim.notify("[fast_agent.nvim] Could not map “" .. short_id .. "” to a conversation.", vim.log.levels.ERROR)
		return
	end

	-- Ask for confirmation before actually deleting:
	vim.ui.select(
		{ "Yes", "No" },
		{ prompt = string.format("Delete “%s” (%s)?", name_to_delete, short_id) },
		function(choice)
			if choice ~= "Yes" then
				vim.notify("[fast_agent.nvim] Deletion cancelled.", vim.log.levels.INFO)
				return
			end

			-- Assume `fast.delete_conversation(id)` actually removes it from core:
			fast.delete_conversation(full_id_to_delete)

			-- Refresh the left list:
			refresh_conversation_list(buf_convos)

			-- If the history buffer was showing this deleted convo, clear it to say “[No active conversation]”:
			local hist_buf = vim.fn.bufnr("FastAgentHistory")
			if hist_buf ~= -1 then
				refresh_message_history(hist_buf)
			end

			vim.notify(string.format(
				"[fast_agent.nvim] Deleted conversation “%s” (%s).",
				name_to_delete, short_id
			), vim.log.levels.INFO)
		end
	)
end

-- ----------------------------------------------------------------------------
-- Map <Space>gh to open this home panel
-- ----------------------------------------------------------------------------
vim.api.nvim_set_keymap(
	"n",
	"<Space>gh",
	"<Cmd>lua require('fast_agent_ui').toggle_home_panel()<CR>",
	{ noremap = true, silent = true }
)

return M
