---@class window.Conversation
---@field id string
---@field directory string
---@field messages window.Message[]

---@class window.Message
---@field role string      # 'user' or 'assistant'
---@field content string   # full message text

---@class window.Input
---@field input_context window.Context[]

---@class window.Context
---@field links window.Link[]
--- Display different previews depending on the buffer

---@class window.Link
---@field line string
---@field origin_file string
---@field origin_row_start integer
---@field origin_col_start integer
---@field origin_row_end integer
---@field origin_col_end integer
--- Or maybe use marks
--- CTRL-]

---@class window.History
---@field conversations window.Conversation[]
---@field current_id string

---@class FastAgentUIApi
---@field list_conversations fun(): table[]             # history listing
---@field get_state fun(): table                        # raw state table
---@field create_new_conversation fun(): string         # start a new conversation
---@field set_current_conversation fun(c_id: string)    # switch active conversation
---@field delete_conversation fun(c_id: string)         # delete conversation
---@field send_text fun(text: string): string           # add user message & save
---@field get_response fun(c_id: string, callback: fun(string))
---@field append_to_file fun(filepath: string, text: string)

local M = {}
local api

--- Initialize the UI module with exactly the methods it needs.
--- @param ag FastAgentUIApi
function M.setup_ui(ag)
  local required = {
    "list_conversations",
    "get_state",
    "create_new_conversation",
    "set_current_conversation",
    "delete_conversation",
    "send_text",
    "get_response",
    "append_to_file",
  }
  for _, fn in ipairs(required) do
    assert(type(ag[fn]) == "function",
           string.format("fast_agent.ui.window: missing API method '%s'", fn))
  end
  api = ag
end
local home_menu_state = {}

local buf_is_valid = vim.api.nvim_buf_is_valid
local win_is_valid = vim.api.nvim_win_is_valid

local function create_floating_window(opts)
	opts = opts or {}
	assert(opts.width and opts.height and opts.row and opts.col,
		"window: missing width/height/row/col in opts")
	local bufnr = vim.api.nvim_create_buf(false, true)
	local win_opts = {
		style    = opts.style or "minimal",
		relative = "editor",
		row      = opts.row,
		col      = opts.col,
		width    = opts.width,
		height   = opts.height,
		border   = opts.border or "rounded",
	}
	local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)
	return { buf = bufnr, win = winnr }
end


--- Append a message block to a conversation buffer and scroll to bottom

local function append_message(bufnr, winid, sender, lines)
	if not buf_is_valid(bufnr) or not win_is_valid(winid) then
		return
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.iter({ "[" .. sender .. "]", lines, { "" } }):flatten():totable())
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
	vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
end

--- Render the full conversation into the preview buffer

local function render_conversation_preview(conv, bufnr, winid)
	if not buf_is_valid(bufnr) or not win_is_valid(winid) then
		return
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
	for _, msg in ipairs(conv.messages or {}) do
		append_message(bufnr, winid, msg.role or msg.sender or "?", vim.split(msg.content or "", "\n"))
	end
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

--- Open the three-pane floating UI: history (left), conversation preview (top-right), input (bottom-right)
function M.toggle_home_menu()
	-- toggle home menu: close if already open
	if home_menu_state.history and win_is_valid(home_menu_state.history.win) then
		for _, wb in pairs(home_menu_state) do
			if win_is_valid(wb.win) then
				vim.api.nvim_win_close(wb.win, true)
			end
			if buf_is_valid(wb.buf) then
				vim.api.nvim_buf_delete(wb.buf, { force = true })
			end
		end
		home_menu_state = {}
		return
	end
	-- overall editor size
	local ui                     = vim.api.nvim_list_uis()[1]
	local total_cols, total_rows = ui.width, ui.height - 1

	-- compute pane dimensions
	local hist_w                 = math.floor(total_cols * 0.20)
	local convo_w                = total_cols - hist_w

	local convo_h                = math.floor(total_rows * 0.80)
	local input_h                = total_rows - convo_h

	-- define window layouts
	local win_defs               = {
		history = { row = 0, col = 0, width = hist_w - 2, height = total_rows - 2, border = "rounded" },
		convo   = { row = 0, col = hist_w, width = convo_w - 2, height = convo_h - 2, border = "rounded" },
		input   = { row = convo_h, col = hist_w, width = convo_w - 2, height = input_h - 2, border = "rounded" },
	}

	-- create floating windows
	local history                = create_floating_window(win_defs.history)
	local convo                  = create_floating_window(win_defs.convo)
	local input                  = create_floating_window(win_defs.input)
	-- track for toggling
	home_menu_state.history      = history
	home_menu_state.convo        = convo
	home_menu_state.input        = input

	-- populate history buffer with conversation scopes (cwd)
  local state_tbl              = api.get_state()
  local convos                 = api.list_conversations()
	local tree_lines             = {}
	for _, c in ipairs(convos) do
		local info = state_tbl.conversations[c.id]
		table.insert(tree_lines, info and info.cwd or c.id)
	end
	vim.api.nvim_buf_set_name(history.buf, "FastAgentHistory")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = history.buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = history.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = history.buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = history.buf })
	vim.api.nvim_buf_set_lines(history.buf, 0, -1, false, tree_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = history.buf })
	-- initial preview of first conversation
	vim.api.nvim_win_set_cursor(history.win, { 1, 0 })
	if #convos > 0 then
		local first = convos[1]
		local conv = state_tbl.conversations[first.id]
		if conv then
			render_conversation_preview(conv, convo.buf, convo.win)
		end
	end

	-- preview on cursor move in history pane
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = history.buf,
		callback = function()
			local ln = vim.api.nvim_win_get_cursor(history.win)[1]
			local sel = convos[ln]
			if sel then
				local conv = state_tbl.conversations[sel.id]
				if conv then
					render_conversation_preview(conv, convo.buf, convo.win)
				end
			end
		end,
	})

	-- navigation between panes via Tab and Shift-Tab
	local function goto_window(win, start_insert)
		vim.api.nvim_set_current_win(win)
		if start_insert then vim.cmd("startinsert") end
	end
	local function goto_next()
		local cur = vim.api.nvim_get_current_win()
		if cur == history.win then
			goto_window(convo.win)
		elseif cur == convo.win then
			goto_window(input.win, true)
		else
			goto_window(history.win)
		end
	end
	local function goto_prev()
		local cur = vim.api.nvim_get_current_win()
		if cur == history.win then
			goto_window(input.win, true)
		elseif cur == convo.win then
			goto_window(history.win)
		else
			goto_window(convo.win)
		end
	end

	local opts = { noremap = true, silent = true, nowait = true }
	-- keymaps for history window
	vim.api.nvim_buf_set_keymap(history.buf, "n", "<CR>", "", vim.tbl_extend("force", opts, {
		callback = function()
			local ln = vim.api.nvim_win_get_cursor(history.win)[1]
			local sel = convos[ln]
			if not sel then return end
        api.set_current_conversation(sel.id)
			local conv = state_tbl.conversations[sel.id]
			if conv then
				render_conversation_preview(conv, convo.buf, convo.win)
			end
			vim.api.nvim_set_current_win(input.win)
			vim.cmd("startinsert")
		end,
	}))
	vim.api.nvim_buf_set_keymap(history.buf, "n", "n", "", vim.tbl_extend("force", opts, {
		callback = function()
			vim.ui.input({ prompt = "New conversation name: " }, function(input_name)
				if not input_name or input_name:match("^%s*$") then return end
          local c_id = api.create_new_conversation()
          api.set_current_conversation(c_id)
				-- refresh history list
          local convos_new = api.list_conversations()
				local lines = {}
				for _, c in ipairs(convos_new) do
					local info = state_tbl.conversations[c.id]
					table.insert(lines, info and info.cwd or c.id)
				end
				vim.api.nvim_buf_set_option_value("modifiable", true, { buf = history.buf })
				vim.api.nvim_buf_set_lines(history.buf, 0, -1, false, lines)
				vim.api.nvim_buf_set_option_value("modifiable", false, { buf = history.buf })
			end)
		end,
	}))
	vim.api.nvim_buf_set_keymap(history.buf, "n", "d", "", vim.tbl_extend("force", opts, {
		callback = function()
			local ln = vim.api.nvim_win_get_cursor(history.win)[1]
			local sel = convos[ln]
			if not sel then return end
			local short = sel.id:sub(1, 8)
			vim.ui.select({ "Yes", "No" }, { prompt = string.format("Delete conversation %s?", short) }, function(choice)
				if choice ~= "Yes" then return end
          api.delete_conversation(sel.id)
				-- refresh history list
          local convos_new = api.list_conversations()
				local lines = {}
				for _, c in ipairs(convos_new) do
					local info = state_tbl.conversations[c.id]
					table.insert(lines, info and info.cwd or c.id)
				end
				vim.api.nvim_buf_set_option_value("modifiable", true, { buf = history.buf })
				vim.api.nvim_buf_set_lines(history.buf, 0, -1, false, lines)
				vim.api.nvim_buf_set_option_value("modifiable", false, { buf = history.buf })
				-- clear preview if no conversations left
				if #convos_new == 0 then
					vim.api.nvim_buf_set_option_value("modifiable", true, { buf = convo.buf })
					vim.api.nvim_buf_set_lines(convo.buf, 0, -1, false, {})
					vim.api.nvim_buf_set_option_value("modifiable", false, { buf = convo.buf })
				end
			end)
		end,
	}))
	vim.api.nvim_buf_set_keymap(history.buf, "n", "c", "", vim.tbl_extend("force", opts, {
		callback = function()
			vim.api.nvim_set_current_win(input.win); vim.cmd("startinsert")
		end,
	}))
	vim.api.nvim_buf_set_keymap(history.buf, "n", "q", "", vim.tbl_extend("force", opts, { callback = M.toggle_home_menu }))

	-- keymaps for preview window
	vim.api.nvim_buf_set_keymap(convo.buf, "n", "c", "", vim.tbl_extend("force", opts, {
		callback = function() vim.api.nvim_set_current_win(history.win) end,
	}))
	vim.api.nvim_buf_set_keymap(convo.buf, "n", "q", "", vim.tbl_extend("force", opts, { callback = M.toggle_home_menu }))

	-- keymaps for input window
	vim.api.nvim_buf_set_keymap(input.buf, "i", "<Esc>", "", vim.tbl_extend("force", opts, {
		callback = function() vim.cmd("stopinsert") end,
	}))
	vim.api.nvim_buf_set_keymap(input.buf, "n", "c", "", vim.tbl_extend("force", opts, {
		callback = function() vim.api.nvim_set_current_win(convo.win) end,
	}))
	vim.api.nvim_buf_set_keymap(input.buf, "n", "q", "", vim.tbl_extend("force", opts, { callback = M.toggle_home_menu }))

	-- cycle through panes with Tab / Shift-Tab
	for _, buf in ipairs({ history.buf, convo.buf, input.buf }) do
		vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", vim.tbl_extend("force", opts, { callback = goto_next }))
		vim.api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", vim.tbl_extend("force", opts, { callback = goto_prev }))
	end

	-- setup input buffer as prompt
	vim.api.nvim_buf_set_name(input.buf, "FastAgentInput")
	vim.api.nvim_set_option_value("buftype", "prompt", { buf = input.buf })
	vim.fn.prompt_setprompt(input.buf, "> ")
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = input.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = input.buf })

	-- handle <CR> in input for sending messages
	vim.api.nvim_buf_set_keymap(input.buf, "i", "<CR>", "", {
		noremap = true,
		nowait = true,
		silent = true,
		callback = function()
			local user_lines = vim.api.nvim_buf_get_lines(input.buf, 0, -1, false)
			append_message(convo.buf, convo.win, "user", user_lines)
			if buf_is_valid(input.buf) then
				vim.api.nvim_buf_set_lines(input.buf, 0, -1, false, { "" })
			end

			-- send to agent and append response
        local c_id = api.send_text(table.concat(user_lines, "\n"))
        api.get_response(c_id, function(reply_text)
          api.append_to_file(c_id, reply_text)
          vim.schedule(function()
            if buf_is_valid(convo.buf) and win_is_valid(convo.win) then
              render_conversation_preview(api.get_state().conversations[c_id], convo.buf, convo.win)
            end
          end)
			end)
		end,
	})

	-- switch to input window and enter insert mode
	vim.api.nvim_set_current_win(input.win)
	vim.cmd("startinsert")
end

return {
  toggle_home_menu = M.toggle_home_menu,
  setup_ui         = M.setup_ui,
}
