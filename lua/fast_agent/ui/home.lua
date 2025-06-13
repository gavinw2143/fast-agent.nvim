local fast = require("fast_agent")
local render = require("fast_agent.ui.render")
local actions = require("fast_agent.ui.actions")
local M = {
  win_convos = nil,
  buf_convos = nil,
  win_history = nil,
  buf_history = nil,
  win_input = nil,
  buf_input = nil,
}

--- Toggle the FastAgent home pane (conversation list + history + prompt).
function M.toggle_home_panel()
  if M.win_convos and vim.api.nvim_win_is_valid(M.win_convos) then
    if M.win_input and vim.api.nvim_win_is_valid(M.win_input) then
      vim.api.nvim_win_close(M.win_input, true)
    end
    if M.win_history and vim.api.nvim_win_is_valid(M.win_history) then
      vim.api.nvim_win_close(M.win_history, true)
    end
    if M.win_convos and vim.api.nvim_win_is_valid(M.win_convos) then
      vim.api.nvim_win_close(M.win_convos, true)
    end
    M.win_convos = nil
    M.buf_convos = nil
    M.win_history = nil
    M.buf_history = nil
    M.win_input = nil
    M.buf_input = nil
    return
  end

  local ui = vim.api.nvim_list_uis()[1]
  local total_cols = ui.width
  local total_lines = ui.height - 1

  local conv_w = math.floor(total_cols * 0.20)
  local right_w = total_cols - conv_w
  local hist_h = math.floor(total_lines * 0.80)
  local prompt_h = total_lines - hist_h

  M.buf_convos = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.buf_convos })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.buf_convos })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.buf_convos })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf_convos })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = M.buf_convos })

  M.win_convos = vim.api.nvim_open_win(M.buf_convos, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = conv_w - 2,
    height = total_lines - 2,
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_keymap(
    M.buf_convos,
    "n",
    "<CR>",
    [[<Cmd>lua require("fast_agent.ui").select_conversation()<CR>]],
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    M.buf_convos,
    "n",
    "n",
    [[<Cmd>lua require("fast_agent.ui").create_conversation()<CR>]],
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    M.buf_convos,
    "n",
    "d",
    [[<Cmd>lua require("fast_agent.ui").delete_conversation()<CR>]],
    { noremap = true, silent = true }
  )

  M.buf_history = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.buf_history })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.buf_history })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.buf_history })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf_history })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = M.buf_history })

  M.win_history = vim.api.nvim_open_win(M.buf_history, false, {
    relative = "editor",
    row = 0,
    col = conv_w,
    width = right_w - 2,
    height = hist_h - 2,
    style = "minimal",
    border = "rounded",
  })

  M.buf_input = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = M.buf_input })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.buf_input })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.buf_input })
  vim.fn.prompt_setprompt(M.buf_input, "> ")

  M.win_input = vim.api.nvim_open_win(M.buf_input, false, {
    relative = "editor",
    row = hist_h,
    col = conv_w,
    width = right_w - 2,
    height = prompt_h - 2,
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_keymap(
    M.buf_input,
    "n",
    "c",
    string.format("<Cmd>lua vim.api.nvim_set_current_win(%d)<CR>", M.win_convos),
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    M.buf_convos,
    "n",
    "c",
    string.format("<Cmd>lua vim.api.nvim_set_current_win(%d)<CR>", M.win_input),
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    M.buf_input,
    "i",
    "<CR>",
    [[<C-\><C-n><Cmd>lua require("fast_agent.ui").submit_prompt()<CR>]],
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    M.buf_input,
    "n",
    "<Esc>",
    [[<Cmd>lua vim.api.nvim_buf_set_option(0, "modifiable", true) |
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {}) |
      vim.api.nvim_buf_set_option(0, "modifiable", false) |
      vim.cmd("startinsert")<CR>]],
    { noremap = true, silent = true }
  )

  render.refresh_conversation_list(M.buf_convos)
  render.refresh_message_history(M.buf_history)

  vim.api.nvim_set_current_win(M.win_input)
  vim.cmd("startinsert")
end

return M