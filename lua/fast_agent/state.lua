local Path = require("plenary.path")
local config = require("fast_agent.config")
local utils = require("fast_agent.utils")
local M = {}

local state = {
	conversations = {},
	current = nil,
	last_input = "",
}

local function state_json_path()
	local cfg = config.get_user_config()
	return Path:new(cfg.cache_dir, cfg.json_file):absolute()
end

--- Ensure the cache directory exists.
function M.ensure_cache_dir()
	local cfg = config.get_user_config()
	local p = Path:new(cfg.cache_dir)
	if not p:exists() then
		p:mkdir({ parents = true })
	end
end

--- Save the state table to disk as JSON.
function M.save_state()
	M.ensure_cache_dir()
	local all = {
		conversations = state.conversations,
		current = state.current,
	}
	local encoded = vim.fn.json_encode(all)
	Path:new(state_json_path()):write(encoded, "w")
end

--- Load the state table from disk, if present.
function M.load_state()
	local p = Path:new(state_json_path())
	if p:exists() then
		local content = p:read()
		local ok, tbl = pcall(vim.fn.json_decode, content)
		if ok and type(tbl) == "table" then
			state.conversations = tbl.conversations or {}
			state.current = tbl.current
		end
	end
end

--- Create a new conversation and make it current.
-- @return string Conversation ID
function M.create_new_conversation()
	local c_id = utils.generate_id()
	local timestamp = os.time()
	state.conversations[c_id] = {
		name = "Conversation " .. tostring(#vim.tbl_keys(state.conversations) + 1),
		messages = {},
		last_updated = timestamp,
	}
	state.current = c_id
	M.save_state()
	return c_id
end

--- List all conversations sorted by last updated descending.
-- @return table[]
function M.list_conversations()
	local out = {}
	for id, info in pairs(state.conversations) do
		table.insert(out, {
			id = id,
			name = info.name,
			last_updated = info.last_updated,
		})
	end
	table.sort(out, function(a, b) return a.last_updated > b.last_updated end)
	return out
end

--- Set the current conversation.
-- @param c_id string
function M.set_current_conversation(c_id)
	if not state.conversations[c_id] then
		vim.notify(string.format(
			"[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id
		), vim.log.levels.ERROR)
		return
	end
	state.current = c_id
	M.save_state()
end

--- Delete a conversation by ID.
-- @param c_id string
function M.delete_conversation(c_id)
	if not state.conversations[c_id] then
		vim.notify(string.format(
			"[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id
		), vim.log.levels.ERROR)
		return
	end
	state.conversations[c_id] = nil
	state.current = nil
	M.save_state()
end

--- Get the current conversation ID, or nil.
-- @return string?
function M.get_current_conversation_id()
	return state.current
end

--- Returns internal state (conversations, current, last_input).
-- @return table
function M.get_state()
	return {
		conversations = state.conversations,
		current = state.current,
		last_input = state.last_input,
	}
end

--- Add a user message to a conversation (or create new).
-- @param text string
-- @param opts table?
function M.send_text(text, opts)
	opts = opts or {}
	local c_id = opts.conversation or state.current
	if not c_id or not state.conversations[c_id] then
		c_id = M.create_new_conversation()
	end
	table.insert(state.conversations[c_id].messages, {
		role = "user",
		content = text,
	})
	state.conversations[c_id].last_updated = os.time()
	M.save_state()
	return c_id
end

return M

