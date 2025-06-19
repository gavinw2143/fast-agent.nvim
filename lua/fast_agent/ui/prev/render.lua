local fast = require("fast_agent")
local M = {}

--- Populate the conversation list buffer.
-- @param bufnr number
function M.refresh_conversation_list(bufnr)
	local convos = fast.list_conversations()
	local lines = {}

	if vim.tbl_isempty(convos) then
		lines = { "[No conversations yet]" }
	else
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

--- Populate the directory messages buffer.
-- @param bufnr number
function M.refresh_directory_messages(bufnr)
	local state = fast.get_state()
	local convs = state.conversations
	local lines = {}
	if vim.tbl_isempty(convs) then
		lines = { "[No messages yet]" }
	else
		local latest = {}
		for _, conv in pairs(convs) do
			if conv.cwd then
				local prev = latest[conv.cwd]
				if not prev or conv.last_updated > prev then
					latest[conv.cwd] = conv.last_updated
				end
			end
		end
		local entries = {}
		for cwd, ts in pairs(latest) do
			table.insert(entries, { cwd = cwd, ts = ts })
		end
		table.sort(entries, function(a, b) return a.ts > b.ts end)
		local basenames = {}
		for _, e in ipairs(entries) do
			local name = vim.fn.fnamemodify(e.cwd, ":t")
			basenames[name] = (basenames[name] or 0) + 1
		end
		local win = vim.fn.bufwinid(bufnr)
		local width = (win ~= -1 and vim.api.nvim_win_get_width(win)) or 80
		for _, e in ipairs(entries) do
			local name = vim.fn.fnamemodify(e.cwd, ":t")
			local disp
			if basenames[name] == 1 then
				disp = name .. "/"
			else
				local parent = vim.fn.fnamemodify(e.cwd, ":h:t")
				disp = parent .. "/" .. name .. "/"
			end
			if #disp >= 20 then
				disp = disp:sub(1, 17) .. "..."
			end
			local when = os.date("%Y-%m-%d %H:%M", e.ts)
			local pad = width - #disp - #when
			if pad < 1 then pad = 1 end
			table.insert(lines, disp .. string.rep(" ", pad) .. when)
		end
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

--- Populate the message messages buffer.
-- @param bufnr number
function M.refresh_message_messages(bufnr)
	local c_id = fast.get_current_conversation_id()
	if not c_id then
		vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No active conversation" })
		vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
		return
	end

	local state = fast.get_state()
	local convo = state.conversations[c_id] or { messages = {} }
	local lines = {}

	for _, msg in ipairs(convo.messages) do
		local prefix = (msg.role == "user") and "> " or ":: "
		local content_lines = vim.split(msg.content, "\n")

		for i, cl in ipairs(content_lines) do
			if i == 1 then
				table.insert(lines, prefix .. cl)
			else
				table.insert(lines, string.rep(" ", #prefix) .. cl)
			end
		end

		table.insert(lines, "")
	end

	if #lines == 0 then
		lines = { "[Conversation is empty]" }
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { #lines, 0 })
	end
end

return M
