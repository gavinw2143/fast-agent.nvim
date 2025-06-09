-- Adjust package path so Lua can find fast_agent.lua
package.path = table.concat({
  'lua/?.lua',
  package.path
}, ';')

local fast = require('fast_agent')

describe('conversation management', function()
  it('creates a new conversation and lists it', function()
    local id = fast.create_new_conversation()
    local list = fast.list_conversations()
    local found = false
    for _, c in ipairs(list) do
      if c.id == id then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)
end)
