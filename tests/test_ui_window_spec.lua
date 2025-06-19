-- Adjust package path so Lua can find plugin modules
package.path = table.concat({
  'lua/?.lua',
  package.path,
}, ';')

describe('UI window internals', function()
  local window
  local calls

  setup(function()
    calls = {}
    _G.vim = {
      api = {
        nvim_buf_is_valid = function(buf) table.insert(calls, {fn='buf_is_valid', buf=buf}); return true end,
        nvim_win_is_valid = function(win) table.insert(calls, {fn='win_is_valid', win=win}); return true end,
        nvim_set_option_value = function(option, value, opts) table.insert(calls, {fn='set_option', option=option, value=value, opts=opts}) end,
        nvim_buf_set_lines = function(buf, start, stop, strict, data) table.insert(calls, {fn='buf_set_lines', buf=buf, start=start, stop=stop, strict=strict, data=data}) end,
        nvim_win_set_cursor = function(win, pos) table.insert(calls, {fn='win_set_cursor', win=win, pos=pos}) end,
        nvim_buf_line_count = function(buf) table.insert(calls, {fn='buf_line_count', buf=buf}); return 42 end,
        nvim_create_buf = function(listed, scratch) table.insert(calls, {fn='create_buf', listed=listed, scratch=scratch}); return 10 end,
        nvim_open_win = function(buf, enter, opts) table.insert(calls, {fn='open_win', buf=buf, enter=enter, opts=opts}); return 20 end,
      },
      fn = { prompt_setprompt = function() end },
      cmd = function() end,
      schedule = function(fn) fn() end,
      ui = { input = function(_, cb) cb() end, select = function(_, _, cb) cb() end },
    }
    window = require('fast_agent.ui.window')
  end)

  it('create_floating_window returns buf and win', function()
    calls = {}
    local w = window._create_floating_window({row=1, col=2, width=3, height=4, border='single', style='minimal'})
    assert.are.equal(10, w.buf)
    assert.are.equal(20, w.win)
    assert.are.same('create_buf', calls[1].fn)
    assert.are.same('open_win', calls[2].fn)
  end)

  it('append_message writes lines and cursor', function()
    calls = {}
    window._append_message(1, 2, 'user', {'hello', 'world'})
    local fn_names = vim.tbl_map(function(call) return call.fn end, calls)
    assert.is_true(vim.tbl_contains(fn_names, 'set_option'))
    assert.is_true(vim.tbl_contains(fn_names, 'buf_set_lines'))
    assert.is_true(vim.tbl_contains(fn_names, 'win_set_cursor'))
  end)

  it('render_conversation_preview clears and appends messages', function()
    calls = {}
    local conv = { messages = { {role='assistant', content='line1\nline2'} } }
    window._render_conversation_preview(conv, 1, 2)
    local fn_names = vim.tbl_map(function(call) return call.fn end, calls)
    assert.is_true(vim.tbl_contains(fn_names, 'set_option'))
    assert.is_true(vim.tbl_contains(fn_names, 'buf_set_lines'))
  end)
end)