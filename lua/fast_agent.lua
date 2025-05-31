local vim = vim
local uv  = vim.loop
local Job = require("plenary.job")
local Path = require("plenary.path")
local uuid = require("plenary.uuid")

local M = {}

-- Default config values
local default_config = {
  api_key     = vim.fn.getenv("OPENAI_API_KEY") or "",
  model       = "gpt-3.5-turbo",
  endpoint    = "https://api.openai.com/v1/chat/completions",
  -- Where to store JSON on disk
  cache_dir   = vim.fn.stdpath("data") .. "/fast_agent",
  json_file   = "conversations.json",
}

-- In-memory state and user config
local user_config = {}
local state = {
  conversations = {},
  current       = nil,
}

--
-- Helpers for Persistence                                                  
-- 

-- Ensure cache directory exists
local function ensure_cache_dir()
  local p = Path:new(user_config.cache_dir)
  if not p:exists() then
    p:mkdir({ parents = true })
  end
end

-- Compute full path to JSON file
local function state_json_path()
  return Path:new(user_config.cache_dir, user_config.json_file):absolute()
end

-- Save `state` table to disk as JSON
local function save_state_to_disk()
  ensure_cache_dir()
  local all = {
    conversations = state.conversations,
    current       = state.current,
  }
  local encoded = vim.fn.json_encode(all)
  local p = Path:new(state_json_path())
  p:write(encoded, "w")
end

-- Load `state` table from disk if it exists
local function load_state_from_disk()
  local p = Path:new(state_json_path())
  if p:exists() then
    local content = p:read()
    local ok, tbl = pcall(vim.fn.json_decode, content)
    if ok and type(tbl) == "table" then
      state.conversations = tbl.conversations or {}
      state.current       = tbl.current
    end
  end
end

--
-- Public API: setup()                                                      
--
-- Called once (e.g. in your plugin’s `config = function() require("fast_agent").setup({...}) end`).
-- Merges user opts, loads state from disk, and creates cache dir.
--
function M.setup(opts)
  -- Merge opts over defaults
  user_config = vim.tbl_deep_extend("force", {}, default_config, opts or {})

  -- If no API key was passed in opts, must rely on env var
  if user_config.api_key == "" then
    vim.notify(
      "[fast_agent.nvim] WARNING: OPENAI_API_KEY is empty; chat completions will fail.",
      vim.log.levels.WARN
    )
  end

  -- Ensure cache folder and load existing state
  ensure_cache_dir()
  load_state_from_disk()
end

-- 
-- -- Conversation Management                                                  
-- 

-- Create a brand-new conversation, return its generated ID
local function create_new_conversation()
  -- Use plenary.uuid to generate a random UUID
	local c_id = uuid.new().uuid
	local timestamp = os.time()
  state.conversations[c_id] = {
    name = "Conversation " .. tostring(#vim.tbl_keys(state.conversations) + 1),
    messages = {},
    last_updated = timestamp,
  }
  -- Mark as current
  state.current = c_id
  save_state_to_disk()
  return c_id
end

-- Return a list of { id = <string>, name = <string>, last_updated = <ts> }
function M.list_conversations()
  local out = {}
  for id, info in pairs(state.conversations) do
    table.insert(out, {
      id = id,
      name = info.name,
      last_updated = info.last_updated,
    })
  end
  -- Sort by last_updated descending
  table.sort(out, function(a, b) return a.last_updated > b.last_updated end)
  return out
end

-- Set “current” conversation; must already exist
function M.set_current_conversation(c_id)
  if state.conversations[c_id] == nil then
    vim.notify(string.format(
      "[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id
    ), vim.log.levels.ERROR)
    return
  end
  state.current = c_id
  save_state_to_disk()
end

-- Get the current conversation ID (or nil)
function M.get_current_conversation_id()
  return state.current
end

--
-- send_text() → store a user message (no API call yet)                        
--
-- If opts.conversation is passed, use that. Otherwise use state.current.
-- If neither exists, create a new conversation.
--
-- We only “enqueue” the user’s prompt (role="user"); we do NOT do the OpenAI
-- HTTP request here.  Instead, get_response() will perform the request
-- against the entire message history (both user & assistant) for that convo.
--
function M.send_text(text, opts)
  opts = opts or {}
  local c_id = opts.conversation or state.current
  if not c_id then
    c_id = create_new_conversation()
  end
  if state.conversations[c_id] == nil then
    c_id = create_new_conversation()
  end

  -- Append user message
  table.insert(state.conversations[c_id].messages, {
    role = "user",
    content = text,
  })
  state.conversations[c_id].last_updated = os.time()
  save_state_to_disk()
  return c_id
end

--
-- -- POST to OpenAI & append assistant reply, then callback    
--
---- Usage:
--   require("fast_agent").get_response(<conv_id>, function(response_text)
--     -- do something with response_text (string)
--   end)
--
function M.get_response(c_id, callback)
  callback = callback or function(_) end

  -- Ensure conversation exists
  local convo = state.conversations[c_id]
  if convo == nil then
    vim.notify(string.format(
      "[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id
    ), vim.log.levels.ERROR)
    return
  end

  -- Build the JSON payload
  local payload = {
    model = user_config.model,
    messages = convo.messages,
  }
  local json_data = vim.fn.json_encode(payload)

  -- Prepare the curl command
  -- (You could also use lua-http or any other HTTP library. Here we use plenary.job + curl.)
  local curl_cmd = {
    "curl", "-s",
    "-X", "POST", user_config.endpoint,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. user_config.api_key,
    "-d", json_data,
  }

  -- Run async job
  Job:new({
    command = curl_cmd[1],
    args = { unpack(curl_cmd, 2) },
    on_exit = vim.schedule_wrap(function(job, exit_code)
      if exit_code ~= 0 then
        vim.notify(
          "[fast_agent.nvim] HTTP error (curl exit code " .. exit_code .. ")",
          vim.log.levels.ERROR
        )
        return
      end

      local result = table.concat(job:result(), "")
      if result == "" then
        vim.notify(
          "[fast_agent.nvim] Empty response from OpenAI API.",
          vim.log.levels.ERROR
        )
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, result)
      if not ok or type(decoded) ~= "table" or not decoded.choices then
        vim.notify(
          "[fast_agent.nvim] Failed to parse OpenAI JSON response.",
          vim.log.levels.ERROR
        )
        return
      end

      local choice = decoded.choices[1]
      if not choice or not choice.message or not choice.message.content then
        vim.notify(
          "[fast_agent.nvim] Unexpected OpenAI response structure.",
          vim.log.levels.ERROR
        )
        return
      end

      local assistant_text = choice.message.content

      -- Append assistant message to conversation
      table.insert(convo.messages, {
        role = "assistant",
        content = assistant_text,
      })
      convo.last_updated = os.time()
      save_state_to_disk()

      -- Finally, invoke user callback
      callback(assistant_text)
    end),
  }):start()
end

--
-- append_to_file() → simple file-append                                
-- 
-- Opens (or creates) `filepath`, appends the given `text` + two newlines.
--
function M.append_to_file(filepath, text)
  if filepath == nil or filepath == "" then
    vim.notify("[fast_agent.nvim] append_to_file: invalid path", vim.log.levels.ERROR)
    return
  end

  -- Expand ~ and environment variables
  local fname = vim.fn.expand(filepath)
  -- Ensure directory portion exists
  local dir = Path:new(fname):parent():absolute()
  if dir ~= nil then
    Path:new(dir):mkdir({ parents = true })
  end

  local fd, err = io.open(fname, "a")
  if not fd then
    vim.notify(
      "[fast_agent.nvim] Failed to open file for append: " .. err,
      vim.log.levels.ERROR
    )
    return
  end

  fd:write(text)
  fd:write("\n\n")
  fd:close()
  vim.notify("[fast_agent.nvim] Appended response to: " .. fname, vim.log.levels.INFO)
end

-- 
-- Floating Prompt Interface (open_prompt)                                
-- 
-- We create a minimal floating (input) window.  When the user <Enter>s, we grab
-- the contents of that line(s), close the float, then call on_submit(input_text, c_id).
--
-- opts = {
--   title     = <string> (displayed in winbar),
--   on_submit = function(input_text, conversation_id) end,
--   width     = <number> (optional; default: 60‐80% of columns),
--   height    = <number> (optional; default: 3 lines),
-- }
--
function M.open_prompt(opts)
  opts = opts or {}
  local prompt_title = opts.title or "FastAgent: Enter your prompt"
  local submit_cb    = opts.on_submit or function(_, _) end
  local width        = opts.width or math.floor(vim.o.columns * 0.6)
  local height       = opts.height or 3
  local col          = math.floor((vim.o.columns - width) / 2)
  local row          = math.floor((vim.o.lines - height) / 2)

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "prompt")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)

  -- Open a floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })

  -- Set a title in the winbar
  vim.api.nvim_win_set_option(win, "winbar", " " .. prompt_title)

  -- Enter prompt mode
  vim.fn.prompt_setprompt(buf, "> ")
  vim.cmd("startinsert")

  -- Handle <CR> in the prompt buffer
  vim.api.nvim_buf_set_keymap(buf, "i", "<CR>", [[<C-\><C-n><Cmd>lua require("fast_agent")._handle_submit(]] ..
    tostring(buf) .. "," .. tostring(win) .. [[)<CR>]], { nowait = true, noremap = true, silent = true })
  -- Also map <Esc> to close the window without submitting
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", [[<Cmd>bd!<CR>]], { silent = true })
  
  -- Store the on_submit callback in a temporary table so _handle_submit can find it
  M._pending_prompt = {
    buf = buf,
    win = win,
    on_submit = submit_cb,
  }
end

--
-- Internal: invoked when user <Enter>s in the prompt buffer
--
function M._handle_submit(buf, win)
  -- Read entire buffer contents (all lines) as the prompt
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input_text = table.concat(lines, "\n")

  -- Close the floating window & buffer
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- Determine which conversation to send to (or create new)
  local c_id = state.current
  if not c_id then
    c_id = create_new_conversation()
  end

  -- Enqueue user message
  table.insert(state.conversations[c_id].messages, {
    role = "user",
    content = input_text,
  })
  state.conversations[c_id].last_updated = os.time()
  save_state_to_disk()

  -- Call the callback with (input_text, c_id)
  if M._pending_prompt and M._pending_prompt.on_submit then
    local cb = M._pending_prompt.on_submit
    cb(input_text, c_id)
  end
  -- Clear the stored pending prompt
  M._pending_prompt = nil
end

return M

