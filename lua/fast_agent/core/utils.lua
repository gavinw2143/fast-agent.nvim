local uv = vim.loop
local Path = require("plenary.path")

local M = {}

function M.generate_id()
  local random = uv.hrtime()
  local rand_str = tostring(math.random(0, 2 ^ 31))
  return tostring(random) .. "_" .. rand_str
end

function M.append_to_file(filepath, text)
  if not filepath or filepath == "" then
    vim.notify("[fast_agent.nvim] append_to_file: invalid path", vim.log.levels.ERROR)
    return
  end

  local fname = vim.fn.expand(filepath)
  local dir = Path:new(fname):parent():absolute()
  if dir then
    Path:new(dir):mkdir({ parents = true })
  end

  local fd, err = io.open(fname, "a")
  if not fd then
    vim.notify("[fast_agent.nvim] Failed to open file for append: " .. err, vim.log.levels.ERROR)
    return
  end

  fd:write(text)
  fd:write("\n\n")
  fd:close()
  vim.notify("[fast_agent.nvim] Appended response to: " .. fname, vim.log.levels.INFO)
end

return M