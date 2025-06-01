-- File: ~/.config/nvim/lua/fast_agent_ui.lua

local M = {}

-- Grab the “core” FastAgent module
local fast = require("fast_agent")

-- Utility: compute absolute sizes
local function pct(x, total)
	return math.floor(x * total)
end

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
		-- Decide on the prefix
		local prefix = (msg.role == "user") and "> " or ":: "
		-- Split the content on actual newline characters
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
function M.open_home_panel()
	-- 1) Create a new tab
	vim.cmd("tabnew")

	-- Get absolute UI dimensions (ignore cmdheight & listchars space)
	local total_cols = vim.o.columns
	local total_lines = vim.o.lines

	-- 2) Vertical split: left = 20%, right = 80%
	local left_w = pct(0.20, total_cols)
	vim.cmd("vertical split")
	vim.cmd("vertical resize " .. left_w)

	--------------------------------------------------------------------------------
	-- 3) Setup the LEFT buffer as the “conversation list”
	--------------------------------------------------------------------------------
	local left_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(left_buf, "FastAgentConvos")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = left_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = left_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = left_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = left_buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = left_buf })

	-- Immediately fill it
	refresh_conversation_list(left_buf)

	-- Map <CR> in this buffer to switch conversation
	vim.api.nvim_buf_set_keymap(
		left_buf, "n", "<CR>",
		[[<Cmd>lua require("fast_agent_ui")._select_conversation()<CR>]],
		{ noremap = true, silent = true }
	)

	-- 4) Move to the RIGHT window
	vim.cmd("wincmd l")

	--------------------------------------------------------------------------------
	-- 5) Horizontal split in the RIGHT window: bottom = 20%, top = 80%
	--------------------------------------------------------------------------------
	local msg_w = pct(0.80, total_lines) -- width is implicit when splitting
	vim.cmd("horizontal split")
	vim.cmd("resize " .. msg_w)

	--------------------------------------------------------------------------------
	-- 6) Setup the BOTTOM-RIGHT buffer as the “prompt” (FastAgent input)
	--------------------------------------------------------------------------------
	vim.cmd("wincmd j")
	local prompt_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(prompt_buf, "FastAgentInput")
	vim.api.nvim_set_option_value("buftype", "prompt", { buf = prompt_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = prompt_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = prompt_buf })
	vim.fn.prompt_setprompt(prompt_buf, "> ")

	-- When <CR> is pressed in this prompt, send to FastAgent and refresh history
	vim.api.nvim_buf_set_keymap(
		prompt_buf, "i", "<CR>",
		[[<C-\><C-n><Cmd>lua require("fast_agent_ui")._submit_prompt()<CR>]],
		{ noremap = true, silent = true }
	)
	-- <Esc> should just close the prompt buffer
	vim.api.nvim_buf_set_keymap(
		prompt_buf, "n", "<Esc>",
		"<Cmd>bd!<CR>",
		{ noremap = true, silent = true }
	)

	-- Enter insert mode immediately
	vim.cmd("startinsert")

	--------------------------------------------------------------------------------
	-- 7) Move UP to set up the TOP-RIGHT buffer as “message history”
	--------------------------------------------------------------------------------
	vim.cmd("wincmd k")
	local msg_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(msg_buf, "FastAgentHistory")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = msg_buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = msg_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = msg_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = msg_buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = msg_buf })

	-- Fill it once at startup
	refresh_message_history(msg_buf)

	--------------------------------------------------------------------------------
	-- 8) Now move the cursor back into the INPUT buffer (bottom-right)
	--------------------------------------------------------------------------------
	vim.cmd("wincmd j")
end

-- ----------------------------------------------------------------------------
-- Called when user presses <CR> in the “prompt” buffer
-- ----------------------------------------------------------------------------
function M._submit_prompt()
	-- Identify which buffer is the prompt and which is history
	local prompt_buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
	local input_text = table.concat(lines, "\n")

	-- Close the prompt buffer & window
	local prompt_win = vim.fn.bufwinid(prompt_buf)
	if prompt_win ~= -1 then
		vim.api.nvim_win_close(prompt_win, true)
	end
	if vim.api.nvim_buf_is_valid(prompt_buf) then
		vim.api.nvim_buf_delete(prompt_buf, { force = true })
	end

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
			local left_buf = vim.fn.bufnr("FastAgentConvos")
			if left_buf ~= -1 then
				refresh_conversation_list(left_buf)
			end
		end)
	end)
end

-- ----------------------------------------------------------------------------
-- Called when user hits <CR> in the “conversation list” buffer
-- ----------------------------------------------------------------------------
function M._select_conversation()
	local left_buf = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)[1] -- 1-based line number
	local line = vim.api.nvim_buf_get_lines(left_buf, cursor_pos - 1, cursor_pos, false)[1]
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
			refresh_conversation_list(left_buf)
			return
		end
	end
	vim.notify("[fast_agent.nvim] Could not find conversation for line: " .. line, vim.log.levels.ERROR)
end

-- ----------------------------------------------------------------------------
-- Map <Space>gh to open this home panel
-- ----------------------------------------------------------------------------
vim.api.nvim_set_keymap(
	"n",
	"<Space>gh",
	"<Cmd>lua require('fast_agent_ui').open_home_panel()<CR>",
	{ noremap = true, silent = true }
)

return M
