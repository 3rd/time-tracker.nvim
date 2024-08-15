local TimeTracker = require("time-tracker/tracker").TimeTracker
local ui = require("time-tracker/ui")

--- @type Config
local default_config = {
  data_file = vim.fn.stdpath("data") .. "/time-tracker.sqlite",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 5 * 60,
}

--- @param user_config Config
local setup = function(user_config)
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

  if not vim.fn.isdirectory(vim.fn.fnamemodify(config.data_file, ":h")) then
    error("Invalid data file path: " .. config.data_file)
  end

  if config.tracking_timeout_seconds <= 0 then
    error("Invalid tracking timeout value: " .. config.tracking_timeout_seconds)
  end

  local tracker = TimeTracker:new(config)

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
