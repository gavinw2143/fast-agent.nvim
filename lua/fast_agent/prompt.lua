local state = require("fast_agent.state")
local M = {}

--- Open a floating prompt window for user input.
-- @param opts table
function M.open_prompt(opts)
  opts = opts or {}
  local prompt_title = opts.title or "FastAgent: Enter your prompt"
  local submit_cb = opts.on_submit or function() end
  local width = opts.width or math.floor(vim.o.columns * 0.6)
  local height = opts.height or 3
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })
  vim.api.nvim_set_option_value("winbar", prompt_title, { win = win })

  vim.fn.prompt_setprompt(buf, "> ")
  vim.cmd("startinsert")

  vim.api.nvim_buf_set_keymap(
    buf,
    "i",
    "<CR>",
    [[<C-\><C-n><Cmd>lua require("fast_agent.prompt")._handle_submit(]]
      .. tostring(buf)
      .. ","
      .. tostring(win)
      .. [[)<CR>]],
    { nowait = true, noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", [[<Cmd>bd!<CR>]], { silent = true })

  M._pending_prompt = { buf = buf, win = win, on_submit = submit_cb }
end

--- Internal: handle <Enter> in prompt buffer.
-- @param buf number
-- @param win number
function M._handle_submit(buf, win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input_text = table.concat(lines, "\n")

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  local c_id = state.get_current_conversation_id()
  if not c_id then
    c_id = state.create_new_conversation()
  end

  state.send_text(input_text)

  if M._pending_prompt and M._pending_prompt.on_submit then
    M._pending_prompt.on_submit(input_text, c_id)
  end
  M._pending_prompt = nil
end

return M