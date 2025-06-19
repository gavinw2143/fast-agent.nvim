local M = {}

function M.install_default_keymaps()
  local opts = { silent = true }
  vim.keymap.set(
    "n",
    "<Space>gh",
    "<Cmd>lua require('fast_agent.ui.window').toggle_home_menu()<CR>",
    opts
  )
end

return M