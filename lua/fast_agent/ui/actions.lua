local fast = require("fast_agent")
local render = require("fast_agent.ui.render")
local home = require("fast_agent.ui.home")
local M = {}

function M.select_conversation()
	local buf_convos = home.buf_convos or -1
	local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]
	local line = ""
	if buf_convos ~= -1 then
		line = vim.api.nvim_buf_get_lines(buf_convos, cursor_pos - 1, cursor_pos, false)[1] or ""
	end
	if line == "" or line:match("^%[No") then
		return
	end

	local short_id = line:sub(1, 8)
	local state = fast.get_state()
	for full_id, info in pairs(state.conversations) do
		if full_id:sub(1, 8) == short_id then
			fast.set_current_conversation(full_id)
			vim.notify(
				string.format("[fast_agent.nvim] Switched to convo '%s' (%s)", full_id, info.name),
				vim.log.levels.INFO
			)

			if home.buf_history and vim.api.nvim_buf_is_valid(home.buf_history) then
				render.refresh_message_history(home.buf_history)
			end
			if home.buf_convos and vim.api.nvim_buf_is_valid(home.buf_convos) then
				render.refresh_conversation_list(home.buf_convos)
			end
			return
		end
	end
	vim.notify(
		"[fast_agent.nvim] Could not find conversation for line: " .. line,
		vim.log.levels.ERROR
	)
end

function M.create_conversation()
	vim.ui.input({ prompt = "New conversation name: " }, function(input)
		if not input or input:match("^%s*$") then
			vim.notify("[fast_agent.nvim] Aborted: no name given.", vim.log.levels.WARN)
			return
		end

		local c_id = fast.create_new_conversation()
		fast.set_current_conversation(c_id)

		if home.buf_convos and vim.api.nvim_buf_is_valid(home.buf_convos) then
			render.refresh_conversation_list(home.buf_convos)
		end
		if home.buf_history and vim.api.nvim_buf_is_valid(home.buf_history) then
			render.refresh_message_history(home.buf_history)
		end

		vim.notify(
			string.format("[fast_agent.nvim] Created conversation “%s” (%s).", input, c_id),
			vim.log.levels.INFO
		)
	end)
end

function M.delete_conversation()
	if home.buf_convos then
		local buf_convos = home.buf_convos
	else
		return
	end
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf_convos, cursor_line - 1, cursor_line, false)[1] or ""

	if line:match("^%[No") then
		vim.notify("[fast_agent.nvim] No conversation here to delete.", vim.log.levels.WARN)
		return
	end

	local short_id = line:sub(1, 8)
	local state = fast.get_state()
	local full_id, name
	for id, info in pairs(state.conversations) do
		if id:sub(1, 8) == short_id then
			full_id, name = id, info.name
			break
		end
	end

	if not full_id then
		vim.notify(
			"[fast_agent.nvim] Could not map “" .. short_id .. "” to a conversation.",
			vim.log.levels.ERROR
		)
		return
	end

	vim.ui.select(
		{ "Yes", "No" },
		{ prompt = string.format("Delete “%s” (%s)?", name, short_id) },
		function(choice)
			if choice ~= "Yes" then
				vim.notify("[fast_agent.nvim] Deletion cancelled.", vim.log.levels.INFO)
				return
			end

			fast.delete_conversation(full_id)

			if home.buf_convos and vim.api.nvim_buf_is_valid(home.buf_convos) then
				render.refresh_conversation_list(home.buf_convos)
			end
			if home.buf_history and vim.api.nvim_buf_is_valid(home.buf_history) then
				render.refresh_message_history(home.buf_history)
			end

			vim.notify(
				string.format("[fast_agent.nvim] Deleted conversation “%s” (%s).", name, short_id),
				vim.log.levels.INFO
			)
		end
	)
end

function M.submit_prompt()
	local buf = home.buf_input
	local lines = {}
	if buf and buf ~= -1 then
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	end
	local input_text = table.concat(lines, "\n")

	if input_text == "" then
		vim.notify(
			"[fast_agent.nvim] Please type something before submitting.",
			vim.log.levels.WARN
		)
		return
	end

	local c_id = fast.send_text(input_text)
	if home.buf_convos and home.buf_convos ~= -1 then
		render.refresh_conversation_list(home.buf_convos)
	end

	vim.notify(
		string.format("[fast_agent.nvim] Prompt queued in conversation '%s'.", c_id),
		vim.log.levels.INFO
	)

	fast.get_response(c_id, function(_)
		vim.schedule(function()
			if home.buf_history and home.buf_history ~= -1 then
				render.refresh_message_history(home.buf_history)
			end
			if home.buf_convos and home.buf_convos ~= -1 then
				render.refresh_conversation_list(home.buf_convos)
			end
		end)
	end)

	if buf and buf ~= -1 then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	end
	if home.win_input and home.win_input ~= -1 then
		vim.api.nvim_set_current_win(home.win_input)
		vim.cmd("startinsert")
	end
end

return M
