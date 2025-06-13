local M = {}

local default_config = {
  api_key   = vim.fn.getenv("OPENAI_API_KEY") or "",
  model     = "gpt-4.1",
  endpoint  = "https://api.openai.com/v1/responses",
  cache_dir = vim.fn.stdpath("data") .. "/fast_agent",
  json_file = "nodes.json",
}

local user_config = {}

--- Get the current configuration.
-- @return table
function M.get_user_config()
  return user_config
end

--- Setup FastAgent with optional overrides.
-- @param opts table
function M.setup(opts)
  user_config = vim.tbl_deep_extend("force", {}, default_config, opts or {})

  if user_config.use_default_keymaps then
    require("fast_agent.keymaps").install_default_keymaps()
  end

  if user_config.api_key == "" then
    vim.notify(
      "[fast_agent.nvim] WARNING: OPENAI_API_KEY is empty; chat completions will fail.",
      vim.log.levels.WARN
    )
  end

  require("fast_agent.state").ensure_cache_dir()
  require("fast_agent.state").load_state()
end

return M