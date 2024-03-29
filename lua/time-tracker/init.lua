--- @type Config
local default_config = {
  data_file = vim.fn.stdpath("data") .. "/time-tracker.json",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 5 * 60,
  buffer_tracking_enabled = true,
}

--- @param current_buffer number
--- @return boolean
local is_trackable_buffer = function(current_buffer)
  local is_valid = vim.api.nvim_buf_is_valid(current_buffer)
  local is_listed = vim.fn.buflisted(current_buffer) == 1
  local is_file = vim.fn.filereadable(vim.fn.bufname(current_buffer)) == 1
  return is_valid and is_listed and is_file
end

--- @param duration number
--- @return string
local format_duration = function(duration)
  local hours = math.floor(duration / 3600)
  local minutes = math.floor((duration % 3600) / 60)
  local seconds = duration % 60
  return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

--- @param path string
--- @return string
local format_path = function(path)
  return vim.fn.fnamemodify(path, ":~:.")
end

--- @class TimeTracker
local TimeTracker = {}

--- @param config Config
function TimeTracker:new(config)
  local tracker = {
    config = config,
    project = self:get_project(),
    timer = nil,
    session_start = vim.fn.localtime(),
    buffer_durations = {},
    active_buffer = nil,
    active_buffer_path = nil,
    active_buffer_start = vim.fn.localtime(),
  }
  setmetatable(tracker, self)
  self.__index = self
  return tracker
end

--- @return Project
function TimeTracker:get_project()
  local path = vim.fn.getcwd()
  return { path = path }
end

--- @return WorkSession[]
function TimeTracker:load_data()
  local ok, data = pcall(vim.fn.readfile, self.config.data_file)
  if not ok then return {} end
  return vim.fn.json_decode(data)
end

--- @param data WorkSession[]
function TimeTracker:save_data(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({ json }, self.config.data_file)
end

function TimeTracker:write_session_entry()
  local end_timestamp = vim.fn.localtime()
  local total_duration = end_timestamp - self.session_start

  --- @type WorkSession
  local session = {
    path = self.project.path,
    start = self.session_start,
    ["end"] = end_timestamp,
    duration = total_duration,
  }

  if self.config.buffer_tracking_enabled then
    -- update current buffer duration
    if self.active_buffer_path then
      local active_buffer_duration = end_timestamp - self.active_buffer_start
      self.buffer_durations[self.active_buffer_path] = (self.buffer_durations[self.active_buffer_path] or 0)
        + active_buffer_duration
    end

    -- update session
    session.buffers = {}
    for buffer_name, duration in pairs(self.buffer_durations) do
      if duration > 0 then
        table.insert(session.buffers, {
          buffer = buffer_name == "" and "[unknown]" or buffer_name,
          duration = duration,
        })
      end
    end
  end

  local sessions = self:load_data()
  table.insert(sessions, session)
  self:save_data(sessions)
  return session
end

function TimeTracker:reset_timer()
  if self.timer ~= nil then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = vim.loop.new_timer()
  self.timer:start(self.config.tracking_timeout_seconds * 1000, 0, function()
    vim.schedule(function()
      self:write_session_entry()
    end)

    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end)
end

function TimeTracker:handle_activity()
  local current_timestamp = vim.fn.localtime()

  if self.config.buffer_tracking_enabled then
    local current_buffer = vim.api.nvim_get_current_buf()

    if not is_trackable_buffer(current_buffer) then return end

    local current_buffer_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(current_buffer), ":~:.")

    -- new session or buffer change
    if self.timer == nil or current_buffer ~= self.active_buffer or current_buffer_path ~= self.active_buffer_path then
      -- update duration for the previous active buffer
      if self.active_buffer_path then
        local active_buffer_duration = current_timestamp - self.active_buffer_start
        self.buffer_durations[self.active_buffer_path] = (self.buffer_durations[self.active_buffer_path] or 0)
          + active_buffer_duration
      end

      -- update active buffer and start time
      self.active_buffer = current_buffer
      self.active_buffer_path = current_buffer_path
      self.active_buffer_start = current_timestamp
    end
  end

  -- new session
  if self.timer == nil then self.session_start = current_timestamp end

  self:reset_timer()
end

--- @return number
function TimeTracker:get_current_session_duration()
  return vim.fn.localtime() - self.session_start
end

--- @return { [string]: number }
function TimeTracker:get_current_session_file_durations()
  local file_durations = {}

  -- update duration for the current active buffer
  if self.active_buffer_path then
    local current_timestamp = vim.fn.localtime()
    local active_buffer_duration = current_timestamp - self.active_buffer_start
    file_durations[self.active_buffer_path] = (self.buffer_durations[self.active_buffer_path] or 0)
      + active_buffer_duration
  end

  -- add durations for other buffers in the current session
  for buffer_path, duration in pairs(self.buffer_durations) do
    if buffer_path ~= self.active_buffer_path then file_durations[buffer_path] = duration end
  end

  return file_durations
end

--- @return { [string]: number }
function TimeTracker:get_all_time_project_durations()
  local sessions = self:load_data()
  local durations = {}
  for _, session in ipairs(sessions) do
    durations[session.path] = (durations[session.path] or 0) + session.duration
  end
  return durations
end

--- @return { [string]: number }
function TimeTracker:get_all_time_project_file_durations()
  local file_durations = {}

  -- get durations from saved sessions
  local sessions = self:load_data()
  for _, session in ipairs(sessions) do
    if self.config.buffer_tracking_enabled and session.path == self.project.path then
      for _, buffer in ipairs(session.buffers) do
        file_durations[buffer.buffer] = (file_durations[buffer.buffer] or 0) + buffer.duration
      end
    end
  end

  -- get durations from the current session
  local current_session_file_durations = self:get_current_session_file_durations()
  for buffer_path, duration in pairs(current_session_file_durations) do
    file_durations[buffer_path] = (file_durations[buffer_path] or 0) + duration
  end

  return file_durations
end

--- @param tracker TimeTracker
local render_stats = function(tracker)
  local session_duration = tracker:get_current_session_duration()
  local project_durations = tracker:get_all_time_project_durations()
  local current_session_file_durations = tracker:get_current_session_file_durations()
  local project_file_durations = tracker:get_all_time_project_file_durations()

  local sorted_current_session_files = {}
  for file, duration in pairs(current_session_file_durations) do
    table.insert(sorted_current_session_files, { file = file, duration = duration })
  end
  table.sort(sorted_current_session_files, function(a, b)
    return a.duration > b.duration
  end)

  local sorted_project_files = {}
  for file, duration in pairs(project_file_durations) do
    table.insert(sorted_project_files, { file = file, duration = duration })
  end
  table.sort(sorted_project_files, function(a, b)
    return a.duration > b.duration
  end)

  local mode = "current"

  local render_lines = function()
    local lines = {
      "**Time Tracker** | ",
    }

    if mode == "current" then
      lines[1] = lines[1] .. "`(C)urrent Project` (A)ll Projects"
      vim.list_extend(lines, {
        "",
        "Root: `" .. format_path(tracker.project.path) .. "`",
        "",
        "Current session: " .. format_duration(session_duration),
        "All-time: " .. format_duration(project_durations[tracker.project.path] + session_duration),
        "",
        "Files (current session):",
      })

      for _, file in ipairs(sorted_current_session_files) do
        table.insert(lines, string.format("- %s `%s`", format_duration(file.duration), format_path(file.file)))
      end

      vim.list_extend(lines, {
        "",
        "Files (all time):",
      })

      for _, file in ipairs(sorted_project_files) do
        table.insert(lines, string.format("- %s `%s`", format_duration(file.duration), format_path(file.file)))
      end
    else
      lines[1] = lines[1] .. "(C)urrent Project `(A)ll Projects`"
      vim.list_extend(lines, {
        "",
        "Projects:",
      })

      for project_path, duration in pairs(project_durations) do
        table.insert(lines, string.format("- %s `%s`", format_duration(duration), format_path(project_path)))
      end
    end

    return lines
  end

  local lines = render_lines()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false

  local width = vim.opt.columns:get()
  local win_width = math.min(math.floor(width * 0.8), 80)

  local height = vim.opt.lines:get()
  local win_height = math.min(#lines + 4, math.floor(height * 0.8))
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)

  local divider = string.rep("─", win_width)
  table.insert(lines, 2, divider)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local opts = {
    style = "minimal",
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    border = "rounded",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.wo[win].cursorline = true
  -- vim.wo[win].winblend = 10
  vim.wo[win].wrap = true

  local rerender = function(new_mode)
    mode = new_mode
    local updated_lines = render_lines()
    table.insert(updated_lines, 2, divider)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, updated_lines)
    vim.bo[buf].modifiable = false
  end

  local keymap_flags = { noremap = true, silent = true, buffer = 0, nowait = true }
  vim.keymap.set("n", "q", "<cmd>quit<cr>", vim.tbl_extend("force", keymap_flags, { desc = "Close time tracker" }))
  vim.keymap.set("n", "c", function()
    rerender("current")
  end, vim.tbl_extend("force", keymap_flags, { desc = "Show current project stats" }))
  vim.keymap.set("n", "a", function()
    rerender("all")
  end, vim.tbl_extend("force", keymap_flags, { desc = "Show all projects stats" }))
end

--- @param user_config Config
local setup = function(user_config)
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

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
      tracker:write_session_entry()
    end,
  })

  vim.api.nvim_create_user_command("TimeTrackerData", function()
    vim.cmd.edit(config.data_file)
  end, {})
  vim.api.nvim_create_user_command("TimeTracker", function()
    render_stats(tracker)
  end, {})
end

return {
  setup = setup,
}
