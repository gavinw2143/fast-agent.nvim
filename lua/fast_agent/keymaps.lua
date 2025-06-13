local M = {}

--- Install default keymaps for FastAgent commands.
function M.install_default_keymaps()
  local opts = { noremap = true, silent = true }
  vim.keymap.set("n", "<leader>gp", "<Cmd>FastAgentPrompt<CR>", opts)
  vim.keymap.set("n", "<leader>gl", "<Cmd>FastAgentList<CR>", opts)
  vim.keymap.set("n", "<leader>gs", "<Cmd>FastAgentSwitch<CR>", opts)
  vim.keymap.set("n", "<leader>gr", "<Cmd>FastAgentFetch<CR>", opts)
  vim.keymap.set("n", "<leader>ga", "<Cmd>FastAgentAppend<CR>", opts)
  vim.keymap.set(
    "n",
    "<Space>gh",
    "<Cmd>lua require('fast_agent.ui').toggle_home_panel()<CR>",
    opts
  )
end

return M