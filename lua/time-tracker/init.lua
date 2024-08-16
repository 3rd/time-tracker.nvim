local TimeTracker = require("time-tracker.tracker").TimeTracker
local ui = require("time-tracker/ui")
local utils = require("time-tracker/utils")

local supported_storage = { "sqlite", "json" }

--- @type Config
local default_config = {
  data_file = vim.fn.stdpath("data") .. "/time-tracker.sqlite",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 5 * 60,
  storage = "sqlite",
}

--- @param config Config
local get_session_impl = function(config)
  if config.storage == "json" then return require("time-tracker.json_session").JsonSession:new(config) end
  return require("time-tracker.sqlite_session").SqliteSession:new(config)
end

--- @param user_config Config
local setup = function(user_config)
  -- vim.pretty_print(user_config)
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

  if not vim.fn.isdirectory(vim.fn.fnamemodify(config.data_file, ":h")) then
    error("Invalid data file path: " .. config.data_file)
  end

  if config.tracking_timeout_seconds <= 0 then
    error("Invalid tracking timeout value: " .. config.tracking_timeout_seconds)
  end

  if utils.in_array(config.storage, supported_storage) == false then
    error("Invalid storage type: " .. config.storage)
  end

  local session = get_session_impl(config)

  local tracker = TimeTracker:new(session)

  for _, event in ipairs(config.tracking_events) do
    vim.api.nvim_create_autocmd(event, {
      callback = function()
        tracker:handle_activity()
      end,
    })
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      tracker:end_session()
    end,
  })

  vim.api.nvim_create_user_command("TimeTracker", function()
    ui.render(vim.fn.getcwd(), tracker)
  end, {})
end

return {
  setup = setup,
}
