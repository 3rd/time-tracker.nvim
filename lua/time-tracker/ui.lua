local utils = require("time-tracker/utils")

---@param tracker TimeTracker
local get_current_session_file_durations = function(tracker)
  if not tracker.current_session then return {} end
  local file_durations = {}

  for _, root in pairs(tracker.current_session.buffers) do
    for buffer_path, buffer_sessions in pairs(root) do
      for _, session in ipairs(buffer_sessions) do
        local duration = session["end"] - session.start
        file_durations[buffer_path] = (file_durations[buffer_path] or 0) + duration
      end
    end
  end

  if tracker.current_buffer then
    local current_buffer_duration = (vim.fn.localtime() - tracker.current_buffer.start)
    file_durations[tracker.current_buffer.path] = (file_durations[tracker.current_buffer.path] or 0)
      + current_buffer_duration
  end

  return file_durations
end

---@param file_durations { [string]: number }
local get_current_session_duration = function(file_durations)
  return vim.iter(vim.tbl_values(file_durations)):fold(0, function(acc, duration)
    return acc + duration
  end)
end

---@param data Data
---@param cwd CWD
---@param current_session_file_durations { [string]: number }
---@return { [string]: number }
local get_current_project_all_time_file_durations = function(data, cwd, current_session_file_durations)
  local project_file_durations = {}

  -- get durations from data
  for root_key, root in pairs(data.roots) do
    if root_key == cwd then
      for buffer_path, buffer_sessions in pairs(root) do
        for _, session in ipairs(buffer_sessions) do
          local duration = session["end"] - session.start
          project_file_durations[buffer_path] = (project_file_durations[buffer_path] or 0) + duration
        end
      end
    end
  end

  -- get durations from current session
  for buffer_path, duration in pairs(current_session_file_durations) do
    project_file_durations[buffer_path] = (project_file_durations[buffer_path] or 0) + duration
  end

  return project_file_durations
end

---@param tracker TimeTracker
---@param data Data
local get_all_projects_durations = function(tracker, data)
  local project_durations = {}

  -- get durations from data
  for root_key, root in pairs(data.roots) do
    local project_duration = 0
    for _, buffer_sessions in pairs(root) do
      for _, session in ipairs(buffer_sessions) do
        project_duration = project_duration + (session["end"] - session.start)
      end
    end
    project_durations[root_key] = project_duration
  end

  -- get durations from current session
  for root_key, root in pairs(tracker.current_session.buffers) do
    local project_duration = 0
    for _, buffer_sessions in pairs(root) do
      for _, session in ipairs(buffer_sessions) do
        project_duration = project_duration + (session["end"] - session.start)
      end
    end
    project_durations[root_key] = (project_durations[root_key] or 0) + project_duration
  end

  -- get durations from current buffer
  if tracker.current_buffer then
    local project_duration = (vim.fn.localtime() - tracker.current_buffer.start)
    project_durations[tracker.current_buffer.cwd] = (project_durations[tracker.current_buffer.cwd] or 0)
      + project_duration
  end

  return project_durations
end

---@param cwd CWD
---@param tracker TimeTracker
local render = function(cwd, tracker)
  local current_session_file_durations = get_current_session_file_durations(tracker)
  local current_session_total_duration = get_current_session_duration(current_session_file_durations)
  local data = tracker:load_data()
  local current_project_all_time_file_durations =
    get_current_project_all_time_file_durations(data, cwd, current_session_file_durations)
  local project_durations = get_all_projects_durations(tracker, data)

  local sorted_current_session_files = {}
  for file, duration in pairs(current_session_file_durations) do
    table.insert(sorted_current_session_files, { file = file, duration = duration })
  end
  table.sort(sorted_current_session_files, function(a, b)
    return a.duration > b.duration
  end)

  local sorted_project_files = {}
  for file, duration in pairs(current_project_all_time_file_durations) do
    table.insert(sorted_project_files, { file = file, duration = duration })
  end
  table.sort(sorted_project_files, function(a, b)
    return a.duration > b.duration
  end)

  local sorted_project_durations = {}
  for path, duration in pairs(project_durations) do
    table.insert(sorted_project_durations, { path = path, duration = duration })
  end
  table.sort(sorted_project_durations, function(a, b)
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
        "Root: `" .. utils.format_path_friendly(cwd) .. "`",
        "",
        "Current session: " .. utils.format_duration(current_session_total_duration),
        "All-time: " .. utils.format_duration((project_durations[cwd] or 0)),
        "",
        "Files (current session):",
      })

      for _, file in ipairs(sorted_current_session_files) do
        table.insert(
          lines,
          string.format("- %s `%s`", utils.format_duration(file.duration), utils.format_path_friendly(file.file))
        )
      end

      vim.list_extend(lines, {
        "",
        "Files (all time):",
      })

      for _, file in ipairs(sorted_project_files) do
        table.insert(
          lines,
          string.format("- %s `%s`", utils.format_duration(file.duration), utils.format_path_friendly(file.file))
        )
      end
    else
      lines[1] = lines[1] .. "(C)urrent Project `(A)ll Projects`"
      vim.list_extend(lines, {
        "",
        "Projects:",
      })

      local total_dur = 0
      for _, project in ipairs(sorted_project_durations) do
        table.insert(
          lines,
          string.format("- %s `%s`", utils.format_duration(project.duration), utils.format_path_friendly(project.path))
        )
        total_dur = total_dur + project.duration
      end
      vim.list_extend(lines, {
        "",
        "Total Time:"
      })
      table.insert(
        lines,
        string.format("- %s", utils.format_duration(total_dur))
      )
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
  vim.wo[win].concealcursor = "nc"

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

return {
  render = render,
  get_current_session_duration = get_current_session_duration,
  get_current_project_all_time_file_durations = get_current_project_all_time_file_durations,
  get_all_projects_durations = get_all_projects_durations,
  get_current_session_file_durations = get_current_session_file_durations,
}
