-- Minimal Neovim init for running UI tests with plenary.nvim
-- Load plenary and this plugin
vim.cmd('silent! packadd plenary.nvim')
vim.cmd('silent! packadd fast-agent.nvim')

-- Determine project root (two levels up from this file)
local source = debug.getinfo(1, 'S').source:sub(2)
local root = source:match("(.+)/tests/minimal_init.lua$")

-- Prepend lua tree to package.path
package.path = table.concat({
  root .. '/lua/?.lua',
  root .. '/lua/?/init.lua',
  package.path,
}, ';')

-- Override test_harness to use glob instead of find for gathering spec files
local ok_th, test_harness = pcall(require, 'plenary.test_harness')
if ok_th then
  test_harness._find_files_to_run = function(directory)
    local Path = require('plenary.path')
    local specs = {}
    for _, f in ipairs(vim.fn.globpath(directory, '*_spec.lua', false, true)) do
      table.insert(specs, Path:new(f))
    end
    return specs
  end
end