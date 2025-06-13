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

--- Populate the message history buffer.
-- @param bufnr number
function M.refresh_message_history(bufnr)
  local c_id = fast.get_current_conversation_id()
  if not c_id then
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No active conversation" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    return
  end

  local state = fast.get_internal_state()
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