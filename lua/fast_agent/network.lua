local Job = require("plenary.job")
local config = require("fast_agent.config")
local state = require("fast_agent.state")
local M = {}

--- Fetch assistant response for a conversation and update state.
-- @param c_id string
-- @param callback function
function M.get_response(c_id, callback)
  callback = callback or function() end
  local st = state.get_state()
  local convo = st.conversations[c_id]
  if not convo then
    vim.notify(
      string.format("[fast_agent.nvim] Error: conversation '%s' does not exist.", c_id),
      vim.log.levels.ERROR
    )
    return
  end

  local payload = {
    model = config.get_user_config().model,
    messages = convo.messages,
  }
  local json_data = vim.fn.json_encode(payload)

  local curl_cmd = {
    "curl", "-s",
    "-X", config.get_user_config().endpoint,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. config.get_user_config().api_key,
    "-d", json_data,
  }

  Job:new({
    command = curl_cmd[1],
    args = { unpack(curl_cmd, 2) },
    on_exit = vim.schedule_wrap(function(job, exit_code)
      if exit_code ~= 0 then
        vim.notify(
          string.format("[fast_agent.nvim] HTTP error (curl exit code %d)", exit_code),
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
      table.insert(convo.messages, {
        role = "assistant",
        content = assistant_text,
      })
      convo.last_updated = os.time()
      state.save_state()
      callback(assistant_text)
    end),
  }):start()
end

return M