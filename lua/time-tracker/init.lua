local TimeTracker = require("time-tracker/tracker").TimeTracker
local ui = require("time-tracker/ui")

local M = {}

--- @type Config
local default_config = {
  data_file = vim.fn.stdpath("data") .. "/time-tracker.sqlite",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 5 * 60,
}

--- @param user_config Config
M.setup = function(user_config)
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})
  config.data_file = vim.fn.fnamemodify(config.data_file, ":p")

  local data_file_stat = vim.loop.fs_stat(config.data_file)
  if
    vim.fn.isdirectory(vim.fn.fnamemodify(config.data_file, ":h")) == 0
    or data_file_stat and data_file_stat.type ~= "file"
  then
    error("Invalid data file path: " .. config.data_file)
  end

  if config.tracking_timeout_seconds <= 0 then
    error("Invalid tracking timeout value: " .. config.tracking_timeout_seconds)
  end

  local tracker, initialized = TimeTracker:new(config)
  if not tracker then return end

  if initialized then
    local started, retryable = tracker:start_session()
    if not started and not retryable then return end
  end

  M.tracker = tracker

  for _, event in ipairs(config.tracking_events) do
    vim.api.nvim_create_autocmd(event, {
      callback = function()
        M.tracker:handle_activity()
      end,
    })
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.tracker:end_session()
    end,
  })

  vim.api.nvim_create_user_command("TimeTracker", function()
    ui.render(vim.fn.getcwd(), M.tracker)
  end, {})

  vim.api.nvim_create_user_command("TimeTrackerHistory", function()
    ui.show_session_history(M.tracker)
  end, { desc = "View detailed time tracking history" })
end

return M
