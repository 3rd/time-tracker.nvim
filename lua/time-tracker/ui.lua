local utils = require("time-tracker/utils")

local FLOAT_VIEWPORT_RATIO = 0.8
local HISTORY_MINIMUM_SIZE_MESSAGE = "TimeTracker: History needs at least 46 columns and 13 lines."

---@return number, number
local get_screen_size = function()
  local ui = vim.api.nvim_list_uis()[1]
  return ui and ui.width or vim.opt.columns:get(), ui and ui.height or vim.opt.lines:get()
end

---@param line_count number
local get_stats_float_layout = function(line_count)
  local screen_width, screen_height = get_screen_size()
  local width = math.min(80, math.floor(screen_width * FLOAT_VIEWPORT_RATIO), screen_width)
  local height = math.min(line_count + 4, math.floor(screen_height * FLOAT_VIEWPORT_RATIO), screen_height)

  return {
    width = width,
    height = height,
    row = math.floor((screen_height - height) / 2),
    col = math.floor((screen_width - width) / 2),
  }
end

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
    local current_buffer_duration = vim.fn.localtime() - tracker.current_buffer.start
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

  for buffer_path, duration in pairs(current_session_file_durations) do
    project_file_durations[buffer_path] = (project_file_durations[buffer_path] or 0) + duration
  end

  return project_file_durations
end

---@param tracker TimeTracker
---@param data Data
local get_all_projects_durations = function(tracker, data)
  local project_durations = {}

  for root_key, root in pairs(data.roots) do
    local project_duration = 0
    for _, buffer_sessions in pairs(root) do
      for _, session in ipairs(buffer_sessions) do
        project_duration = project_duration + (session["end"] - session.start)
      end
    end
    project_durations[root_key] = project_duration
  end

  for root_key, root in pairs(tracker.current_session.buffers) do
    local project_duration = 0
    for _, buffer_sessions in pairs(root) do
      for _, session in ipairs(buffer_sessions) do
        project_duration = project_duration + (session["end"] - session.start)
      end
    end
    project_durations[root_key] = (project_durations[root_key] or 0) + project_duration
  end

  if tracker.current_buffer then
    local project_duration = vim.fn.localtime() - tracker.current_buffer.start
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
        "All-time: " .. utils.format_duration(project_durations[cwd] or 0),
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

      for _, project in ipairs(sorted_project_durations) do
        table.insert(
          lines,
          string.format("- %s `%s`", utils.format_duration(project.duration), utils.format_path_friendly(project.path))
        )
      end
    end

    return lines
  end

  local lines = render_lines()
  local layout = get_stats_float_layout(#lines)
  local divider = string.rep("─", layout.width)
  table.insert(lines, 2, divider)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    style = "minimal",
    relative = "editor",
    width = layout.width,
    height = layout.height,
    row = layout.row,
    col = layout.col,
    border = "rounded",
  })
  vim.wo[win].cursorline = true
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

  local keymap_flags = { noremap = true, silent = true, buffer = buf, nowait = true }
  vim.keymap.set("n", "q", "<cmd>quit<cr>", vim.tbl_extend("force", keymap_flags, { desc = "Close time tracker" }))
  vim.keymap.set("n", "c", function()
    rerender("current")
  end, vim.tbl_extend("force", keymap_flags, { desc = "Show current project stats" }))
  vim.keymap.set("n", "a", function()
    rerender("all")
  end, vim.tbl_extend("force", keymap_flags, { desc = "Show all projects stats" }))
end

---@param timestamp number
---@return number
local get_local_midnight = function(timestamp)
  local date = os.date("*t", timestamp)
  date.hour = 0
  date.min = 0
  date.sec = 0
  date.isdst = nil
  local midnight = os.time(date)
  if not midnight then error("Failed to calculate a local calendar boundary.") end
  return midnight
end

---@param timestamp number
---@param days number
---@return number
local add_local_days = function(timestamp, days)
  local date = os.date("*t", timestamp)
  date.day = date.day + days
  date.isdst = nil
  local shifted = os.time(date)
  if not shifted then error("Failed to calculate a local calendar boundary.") end
  return shifted
end

---@param timestamp number
---@param week_offset number
---@return number, number
local get_history_week_bounds = function(timestamp, week_offset)
  if type(timestamp) ~= "number" then error("History snapshot time must be a number.") end
  if type(week_offset) ~= "number" or week_offset < 0 or week_offset % 1 ~= 0 then
    error("History week offset must be a non-negative integer.")
  end

  local day_start = get_local_midnight(timestamp)
  local day = os.date("*t", day_start)
  local current_week_start = add_local_days(day_start, -((day.wday + 5) % 7))
  local week_start = add_local_days(current_week_start, -(week_offset * 7))
  return week_start, add_local_days(week_start, 7)
end

---@param data Data
---@param current_session CurrentSession|nil
---@param current_buffer CurrentBuffer|nil
---@param captured_now number
---@return { intervals: table[], project_totals: table<string, number> }
local build_history_snapshot = function(data, current_session, current_buffer, captured_now)
  if type(data) ~= "table" or type(data.roots) ~= "table" then error("Persisted history data is malformed.") end
  if type(captured_now) ~= "number" then error("History snapshot time must be a number.") end

  local snapshot = {
    intervals = {},
    project_totals = {},
  }

  local add_history_interval = function(cwd, path, interval_start, interval_end)
    if type(cwd) ~= "string" or type(path) ~= "string" then return end
    if type(interval_start) ~= "number" or type(interval_end) ~= "number" then return end
    if interval_end <= interval_start then return end

    table.insert(snapshot.intervals, {
      cwd = cwd,
      path = path,
      start = interval_start,
      ["end"] = interval_end,
    })
    snapshot.project_totals[cwd] = (snapshot.project_totals[cwd] or 0) + (interval_end - interval_start)
  end

  for cwd, root in pairs(data.roots) do
    if type(root) == "table" then
      for path, intervals in pairs(root) do
        if type(intervals) == "table" then
          for _, interval in pairs(intervals) do
            if type(interval) == "table" then add_history_interval(cwd, path, interval.start, interval["end"]) end
          end
        end
      end
    end
  end

  if current_session and type(current_buffer) == "table" then
    add_history_interval(current_buffer.cwd, current_buffer.path, current_buffer.start, captured_now)
  end

  return snapshot
end

---@param snapshot { intervals: table[], project_totals: table<string, number> }
---@param range_start number
---@param range_end number
---@param cwd? string
---@return table[]
local get_history_segments = function(snapshot, range_start, range_end, cwd)
  local segments = {}

  for _, interval in ipairs(snapshot.intervals) do
    if (not cwd or interval.cwd == cwd) and interval.start < range_end and interval["end"] > range_start then
      local segment_start = math.max(interval.start, range_start)
      local clipped_end = math.min(interval["end"], range_end)

      while segment_start < clipped_end do
        local day_start = get_local_midnight(segment_start)
        local day_end = add_local_days(day_start, 1)
        local segment_end = math.min(clipped_end, day_end)
        table.insert(segments, {
          cwd = interval.cwd,
          path = interval.path,
          start = segment_start,
          ["end"] = segment_end,
          day_start = day_start,
          day_end = day_end,
        })
        segment_start = segment_end
      end
    end
  end

  return segments
end

---@param snapshot { intervals: table[], project_totals: table<string, number> }
---@param week_start number
---@param week_end number
---@return table[]
local get_history_week_summary = function(snapshot, week_start, week_end)
  local summaries_by_identity = {}

  for _, segment in ipairs(get_history_segments(snapshot, week_start, week_end)) do
    local identity = table.concat({ segment.day_start, segment.day_end, segment.cwd }, "\0")
    local summary = summaries_by_identity[identity]
    if not summary then
      summary = {
        cwd = segment.cwd,
        day_start = segment.day_start,
        day_end = segment.day_end,
        date = os.date("%Y-%m-%d", segment.day_start),
        day = os.date("%a", segment.day_start),
        daily_duration = 0,
        project_total = snapshot.project_totals[segment.cwd],
      }
      summaries_by_identity[identity] = summary
    end
    summary.daily_duration = summary.daily_duration + (segment["end"] - segment.start)
  end

  local summaries = vim.tbl_values(summaries_by_identity)
  table.sort(summaries, function(a, b)
    if a.day_start ~= b.day_start then return a.day_start > b.day_start end
    return a.cwd < b.cwd
  end)
  return summaries
end

---@param snapshot { intervals: table[], project_totals: table<string, number> }
---@param range_start number
---@param range_end number
---@param cwd? string
---@return table[]
local get_history_work_sessions = function(snapshot, range_start, range_end, cwd)
  local sessions = get_history_segments(snapshot, range_start, range_end, cwd)
  table.sort(sessions, function(a, b)
    if a.start ~= b.start then return a.start > b.start end
    if a.cwd ~= b.cwd then return a.cwd < b.cwd end
    return a.path < b.path
  end)
  return sessions
end

---@param text string
---@param width number
---@return string
local truncate_left = function(text, width)
  if width <= 0 then return "" end
  if vim.fn.strdisplaywidth(text) <= width then return text end
  if width == 1 then return "…" end

  local character_count = vim.fn.strchars(text)
  for start = 1, character_count do
    local suffix = vim.fn.strcharpart(text, start)
    if vim.fn.strdisplaywidth(suffix) <= width - 1 then return "…" .. suffix end
  end

  return "…"
end

---@param text string
---@param width number
---@return string
local format_inline_code = function(text, width)
  if width <= 2 then return truncate_left(text, width) end
  return "`" .. truncate_left(text, width - 2) .. "`"
end

---@param week_offset number
---@return string
local get_history_period_label = function(week_offset)
  if week_offset == 0 then return "Current week" end
  if week_offset == 1 then return "1 week ago" end
  return string.format("%d weeks ago", week_offset)
end

---@param week_offset number
---@param width number
---@return string
local format_history_summary_heading = function(week_offset, width)
  local period_label = get_history_period_label(week_offset)
  local period = "`" .. period_label .. "`"
  local heading = "**Weekly summary** | (H) Older (L) Newer | " .. period
  if vim.fn.strdisplaywidth(heading) <= width then return heading end

  heading = "**Weekly summary** | H/L | " .. period
  if vim.fn.strdisplaywidth(heading) <= width then return heading end

  local prefix = "**Weekly summary** | H/L | "
  return prefix .. format_inline_code(period_label, width - vim.fn.strdisplaywidth(prefix))
end

---@param cwd string
---@param path string
---@return string
local get_history_file_display = function(cwd, path)
  local cwd_prefix = cwd == "/" and cwd or cwd:gsub("/+$", "") .. "/"
  if path:sub(1, #cwd_prefix) == cwd_prefix then
    local relative_path = path:sub(#cwd_prefix + 1)
    if relative_path ~= "" then return relative_path end
  end
  return utils.format_path_friendly(path)
end

---@param session table
---@param width number
---@return string
local format_history_work_session = function(session, width)
  local prefix = "- " .. os.date("%I:%M %p", session.start) .. " · "
  local separator = " · "
  local paths_width = width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(separator)
  local project = utils.format_path_friendly(session.cwd)
  local file = get_history_file_display(session.cwd, session.path)
  local project_width = math.max(3, math.min(math.floor(paths_width * 0.4), vim.fn.strdisplaywidth(project) + 2))
  project_width = math.min(project_width, paths_width - 3)
  local file_width = paths_width - project_width

  return prefix .. format_inline_code(project, project_width) .. separator .. format_inline_code(file, file_width)
end

---@param summary table
---@param width number
---@return string
local format_history_summary = function(summary, width)
  local daily_duration = utils.format_duration(summary.daily_duration)
  local project_total = utils.format_duration(summary.project_total)
  local prefix
  local suffix
  if width < 48 then
    prefix = "- " .. summary.date .. " "
    suffix = " " .. daily_duration .. "/" .. project_total .. " d/t"
  elseif width < 64 then
    prefix = "- " .. summary.date .. " · "
    suffix = " · d/t " .. daily_duration .. "/" .. project_total
  else
    prefix = "- " .. summary.date .. " " .. summary.day .. " · "
    suffix = " · daily " .. daily_duration .. " · total " .. project_total
  end
  local project_width = width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(suffix)

  return prefix .. format_inline_code(utils.format_path_friendly(summary.cwd), project_width) .. suffix
end

---@param sessions table[]
---@param width number
---@param empty_work_message string
---@return string[]
local format_history_work_session_lines = function(sessions, width, empty_work_message)
  local lines = {
    "**Work sessions**",
    string.rep("─", width),
  }

  if #sessions == 0 then
    table.insert(lines, empty_work_message)
  else
    for _, session in ipairs(sessions) do
      table.insert(lines, format_history_work_session(session, width))
    end
  end

  return lines
end

---@param summaries table[]
---@param width number
---@param week_offset number
---@return string[], table<number, table>
local format_history_summary_lines = function(summaries, width, week_offset)
  local lines = {
    format_history_summary_heading(week_offset, width),
    string.rep("─", width),
  }

  local summary_line_data = {}
  if #summaries == 0 then
    table.insert(lines, "No tracked time for this week.")
  else
    for _, summary in ipairs(summaries) do
      table.insert(lines, format_history_summary(summary, width))
      summary_line_data[#lines] = summary
    end
  end

  return lines, summary_line_data
end

---@param buf number
---@param lines string[]
local set_scratch_buffer_lines = function(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local get_history_float_layout = function()
  local screen_width, screen_height = get_screen_size()
  if screen_width < 46 or screen_height < 13 then return nil end

  local layout = {
    width = math.floor(screen_width * FLOAT_VIEWPORT_RATIO),
    total_height = math.floor(screen_height * FLOAT_VIEWPORT_RATIO),
  }
  layout.row = math.floor((screen_height - layout.total_height) / 2)
  layout.col = math.floor((screen_width - layout.width - 2) / 2)

  local content_rows = layout.total_height - 4
  layout.top_height = math.floor(content_rows * 0.53 + 0.5)
  layout.top_height = math.max(3, math.min(layout.top_height, content_rows - 3))
  layout.bottom_height = content_rows - layout.top_height
  return layout
end

---@param tracker TimeTracker
local show_session_history = function(tracker)
  local initial_layout = get_history_float_layout()
  if not initial_layout then
    vim.notify(HISTORY_MINIMUM_SIZE_MESSAGE, vim.log.levels.WARN)
    return
  end

  local work_buf
  local work_win
  local summary_buf
  local summary_win
  local autocmd_group
  local closing = false

  local close_history_windows = function()
    if closing then return end
    closing = true
    if autocmd_group then
      pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
      autocmd_group = nil
    end
    if work_win and vim.api.nvim_win_is_valid(work_win) then pcall(vim.api.nvim_win_close, work_win, true) end
    if summary_win and vim.api.nvim_win_is_valid(summary_win) then pcall(vim.api.nvim_win_close, summary_win, true) end
    if work_buf and vim.api.nvim_buf_is_valid(work_buf) then
      pcall(vim.api.nvim_buf_delete, work_buf, { force = true })
    end
    if summary_buf and vim.api.nvim_buf_is_valid(summary_buf) then
      pcall(vim.api.nvim_buf_delete, summary_buf, { force = true })
    end
  end

  local ok, err = pcall(function()
    local captured_now = vim.fn.localtime()
    local current_session = tracker.current_session
    local current_buffer = tracker.current_buffer
    local data = tracker:load_data()
    local snapshot = build_history_snapshot(data, current_session, current_buffer, captured_now)
    local week_offset = 0
    local displayed_week_start
    local displayed_week_end
    local summaries
    local summary_line_data
    local selected_summary
    local details_summary
    local layout = initial_layout
    local rendering = false
    local departed_history_win
    local redirecting_window_navigation = false

    work_buf = vim.api.nvim_create_buf(false, true)
    summary_buf = vim.api.nvim_create_buf(false, true)
    for _, buf in ipairs({ work_buf, summary_buf }) do
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].filetype = "markdown"
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      set_scratch_buffer_lines(buf, { "" })
    end

    local history_windows_are_valid = function()
      return work_win and summary_win and vim.api.nvim_win_is_valid(work_win) and vim.api.nvim_win_is_valid(summary_win)
    end

    local summaries_match = function(left, right)
      return left
        and right
        and left.day_start == right.day_start
        and left.day_end == right.day_end
        and left.cwd == right.cwd
    end

    local find_summary = function(identity)
      for _, summary in ipairs(summaries) do
        if summaries_match(summary, identity) then return summary end
      end
    end

    local find_summary_line = function(identity)
      for line, summary in pairs(summary_line_data) do
        if summaries_match(summary, identity) then return line end
      end
    end

    local refresh_week = function()
      displayed_week_start, displayed_week_end = get_history_week_bounds(captured_now, week_offset)
      summaries = get_history_week_summary(snapshot, displayed_week_start, displayed_week_end)
      selected_summary = summaries[1]
      details_summary = selected_summary
    end

    local render_work_sessions = function(reset_view)
      if not history_windows_are_valid() then return end
      details_summary = find_summary(details_summary)
      local range_start = details_summary and details_summary.day_start or displayed_week_start
      local range_end = details_summary and details_summary.day_end or displayed_week_end
      local sessions =
        get_history_work_sessions(snapshot, range_start, range_end, details_summary and details_summary.cwd)
      local empty_message = details_summary and "No work sessions for this project and date."
        or "No work sessions for this week."
      local lines = format_history_work_session_lines(sessions, layout.width, empty_message)
      set_scratch_buffer_lines(work_buf, lines)
      if reset_view then
        vim.api.nvim_win_call(work_win, function()
          vim.fn.winrestview({ topline = 1 })
        end)
      end
    end

    local render_summary = function(cursor_target, reset_view)
      if not history_windows_are_valid() then return end
      selected_summary = find_summary(selected_summary)
      local lines
      lines, summary_line_data = format_history_summary_lines(summaries, layout.width, week_offset)
      rendering = true
      set_scratch_buffer_lines(summary_buf, lines)

      local cursor_line = cursor_target
      if cursor_target == "selected" then cursor_line = find_summary_line(selected_summary) or 3 end
      cursor_line = math.max(1, math.min(cursor_line, #lines))
      vim.api.nvim_win_set_cursor(summary_win, { cursor_line, 0 })
      if reset_view then
        vim.api.nvim_win_call(summary_win, function()
          vim.fn.winrestview({ topline = 1 })
        end)
      end
      rendering = false
    end

    local configure_history_windows = function()
      vim.api.nvim_win_set_config(work_win, {
        relative = "editor",
        width = layout.width,
        height = layout.top_height,
        row = layout.row,
        col = layout.col,
      })
      vim.api.nvim_win_set_config(summary_win, {
        relative = "editor",
        width = layout.width,
        height = layout.bottom_height,
        row = layout.row + layout.top_height + 2,
        col = layout.col,
      })
    end

    local show_older_week = function()
      week_offset = week_offset + 1
      refresh_week()
      render_summary("selected", true)
      render_work_sessions(true)
    end

    local show_newer_week = function()
      if week_offset == 0 then return end
      week_offset = week_offset - 1
      refresh_week()
      render_summary("selected", true)
      render_work_sessions(true)
    end

    work_win = vim.api.nvim_open_win(work_buf, false, {
      relative = "editor",
      width = layout.width,
      height = layout.top_height,
      row = layout.row,
      col = layout.col,
      style = "minimal",
      border = "rounded",
    })
    summary_win = vim.api.nvim_open_win(summary_buf, true, {
      relative = "editor",
      width = layout.width,
      height = layout.bottom_height,
      row = layout.row + layout.top_height + 2,
      col = layout.col,
      style = "minimal",
      border = "rounded",
    })
    for _, history_win in ipairs({ work_win, summary_win }) do
      vim.wo[history_win].wrap = true
      vim.wo[history_win].concealcursor = "nc"
    end
    vim.wo[work_win].cursorline = false
    vim.wo[summary_win].cursorline = true

    refresh_week()
    render_summary("selected", true)
    render_work_sessions(true)

    local mapping_options = { noremap = true, silent = true, nowait = true }
    for _, buf in ipairs({ work_buf, summary_buf }) do
      vim.keymap.set(
        "n",
        "q",
        close_history_windows,
        vim.tbl_extend("force", mapping_options, { buffer = buf, desc = "Close time tracker history" })
      )
      vim.keymap.set(
        "n",
        "H",
        show_older_week,
        vim.tbl_extend("force", mapping_options, { buffer = buf, desc = "Show older week" })
      )
      vim.keymap.set(
        "n",
        "L",
        show_newer_week,
        vim.tbl_extend("force", mapping_options, { buffer = buf, desc = "Show newer week" })
      )
    end

    autocmd_group =
      vim.api.nvim_create_augroup(string.format("TimeTrackerHistory%d_%d", work_buf, summary_buf), { clear = true })
    vim.api.nvim_create_autocmd("WinLeave", {
      group = autocmd_group,
      callback = function()
        if closing or redirecting_window_navigation then return end
        local leaving_win = vim.api.nvim_get_current_win()
        if leaving_win == work_win or leaving_win == summary_win then departed_history_win = leaving_win end
      end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
      group = autocmd_group,
      callback = function()
        if closing or redirecting_window_navigation or not departed_history_win then return end
        if not history_windows_are_valid() then
          departed_history_win = nil
          return
        end

        local entered_win = vim.api.nvim_get_current_win()
        if entered_win == work_win or entered_win == summary_win then
          departed_history_win = nil
          return
        end

        local target_win = departed_history_win == work_win and summary_win or work_win
        departed_history_win = nil
        redirecting_window_navigation = true
        vim.api.nvim_set_current_win(target_win)
        redirecting_window_navigation = false
      end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = autocmd_group,
      buffer = summary_buf,
      callback = function()
        if rendering or not history_windows_are_valid() then return end
        local cursor_line = vim.api.nvim_win_get_cursor(summary_win)[1]
        local summary = summary_line_data[cursor_line]
        if summary then
          if summaries_match(details_summary, summary) then return end
          selected_summary = summary
          details_summary = summary
          render_work_sessions(true)
        elseif details_summary then
          details_summary = nil
          render_work_sessions(true)
        end
      end,
    })
    for _, history_win in ipairs({ work_win, summary_win }) do
      vim.api.nvim_create_autocmd("WinClosed", {
        group = autocmd_group,
        pattern = tostring(history_win),
        callback = close_history_windows,
      })
    end
    vim.api.nvim_create_autocmd("VimResized", {
      group = autocmd_group,
      callback = function()
        if rendering then return end
        if not history_windows_are_valid() then
          close_history_windows()
          return
        end
        local resized_layout = get_history_float_layout()
        if not resized_layout then
          close_history_windows()
          vim.notify(HISTORY_MINIMUM_SIZE_MESSAGE, vim.log.levels.WARN)
          return
        end
        local focused_win = vim.api.nvim_get_current_win()
        local cursor_line = vim.api.nvim_win_get_cursor(summary_win)[1]
        local summary = summary_line_data[cursor_line]
        if summary then
          selected_summary = find_summary(summary)
          details_summary = selected_summary
        else
          details_summary = nil
        end
        layout = resized_layout
        configure_history_windows()
        render_summary(summary and "selected" or cursor_line, true)
        render_work_sessions(true)
        if focused_win == work_win then
          vim.api.nvim_set_current_win(work_win)
        elseif focused_win == summary_win then
          vim.api.nvim_set_current_win(summary_win)
        end
      end,
    })
  end)

  if ok then return end

  close_history_windows()
  vim.notify("TimeTracker: Failed to load history. Error: " .. tostring(err), vim.log.levels.ERROR)
end

return {
  render = render,
  get_current_session_duration = get_current_session_duration,
  get_current_project_all_time_file_durations = get_current_project_all_time_file_durations,
  get_all_projects_durations = get_all_projects_durations,
  get_current_session_file_durations = get_current_session_file_durations,
  build_history_snapshot = build_history_snapshot,
  get_history_week_bounds = get_history_week_bounds,
  get_history_week_summary = get_history_week_summary,
  get_history_work_sessions = get_history_work_sessions,
  show_session_history = show_session_history,
}
