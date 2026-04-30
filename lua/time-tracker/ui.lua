local utils = require("time-tracker/utils")

local M = {}

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

-- Add this to the M table at the bottom of the file
function M.show_session_history(tracker)
  local db_path = tracker.config.data_file
  local sqlite_bin = vim.g.time_tracker_sqlite_bin or "sqlite3"
  local ns_id = vim.api.nvim_create_namespace("TrackerSelection")

  vim.api.nvim_set_hl(0, "TrackerHeader", { fg = "#808080", italic = true })
  vim.api.nvim_set_hl(0, "WorkSessionGreen", { link = "String" })
  vim.api.nvim_set_hl(0, "SummaryWhite", { link = "Normal" })
  vim.api.nvim_set_hl(0, "SeparatorColor", { link = "Comment" })
  vim.api.nvim_set_hl(0, "ActiveRowBlue", { fg = "#000000", bg = "#4682b4", bold = true })
  vim.api.nvim_set_hl(0, "MatchRowBlue", { bg = "#2c3e50" })

  local function get_sql_output(query)
    local cmd = string.format('%s %s "%s"', sqlite_bin, db_path, query:gsub("\n", " "))
    local handle = io.popen(cmd)
    if not handle then return "" end
    local res = handle:read("*a")
    handle:close()
    return res:gsub("^%s*(.-)%s*$", "%1")
  end

  local function format_time(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dmin", h, m)
  end

  -- 2. WINDOW SELECTION & CREATION
  local stats = vim.api.nvim_list_uis()[1]
  local total_w, total_h = 87, 34
  local top_h, bot_h = 16, 14
  local root_opts = {
    relative = "editor",
    width = total_w,
    col = (stats.width - total_w) / 2,
    row = (stats.height - total_h) / 2,
    style = "minimal",
    border = "rounded",
    title_pos = "center",
  }

  local top_buf = vim.api.nvim_create_buf(false, true)
  local top_win = vim.api.nvim_open_win(top_buf, false,
    vim.tbl_extend("force", root_opts, { height = top_h, title = " WORK SESSIONS " }))
  local bot_buf = vim.api.nvim_create_buf(false, true)
  local bot_win = vim.api.nvim_open_win(bot_buf, true,
    vim.tbl_extend("force", root_opts, { height = bot_h, row = root_opts.row + top_h + 2, title = " WEEKLY SUMMARY " }))

  local line_to_data = {}

  -- 3. REFRESH LOGIC (Top Window - Duration Removed)
  -- 3. REFRESH LOGIC (Top Window)
  local function refresh_ui()
    local cursor = vim.api.nvim_win_get_cursor(bot_win)[1]
    local data = line_to_data[cursor]
    vim.api.nvim_buf_clear_namespace(bot_buf, ns_id, 0, -1)

    local list_sql
    if not data then
      list_sql = [[
        SELECT strftime('%H:%M', s.start_time, 'unixepoch', 'localtime'),
               COALESCE(b.cwd, '---'), COALESCE(b.path, '---')
        FROM sessions s LEFT JOIN buffers b ON s.id = b.session_id
        WHERE s.start_time > (strftime('%s', 'now') - 604800)
        AND b.path NOT LIKE '%.lua'
        ORDER BY s.start_time DESC;
      ]]
    else
      list_sql = string.format(
        [[
        SELECT strftime('%%H:%%M', s.start_time, 'unixepoch', 'localtime'),
               COALESCE(b.cwd, '---'), COALESCE(b.path, '---')
        FROM sessions s JOIN buffers b ON s.id = b.session_id
        WHERE strftime('%%m/%%d', s.start_time, 'unixepoch', 'localtime') = '%s'
        AND b.cwd LIKE '%%%s%%'
        AND b.path NOT LIKE '%%.lua'
        ORDER BY s.start_time DESC;
        ]],
        data.date,
        data.project_root
      )

      -- Highlight logic remains the same...
      for line_num, info in pairs(line_to_data) do
        if line_num == cursor then
          vim.api.nvim_buf_add_highlight(bot_buf, ns_id, "ActiveRowBlue", line_num - 1, 0, -1)
        elseif info.project_root == data.project_root then
          vim.api.nvim_buf_add_highlight(bot_buf, ns_id, "MatchRowBlue", line_num - 1, 0, -1)
        end
      end
    end

    local list_result = get_sql_output(list_sql)

    -- Fixed format string to ensure columns are perfectly vertical
    local top_format = " %-10s | %-20s | %-45s"
    local lines = {
      "",
      string.format(top_format, "Time", "Module", "File"),
      string.rep("─", total_w),
    }

    for line in list_result:gmatch("[^\r\n]+") do
      local p = vim.split(line, "|")
      if #p >= 3 then
        local module_name = vim.fn.fnamemodify(p[2], ":t")
        local file_name = vim.fn.fnamemodify(p[3], ":t")

        table.insert(
          lines,
          string.format(top_format, p[1], module_name, file_name)
        )
      end
    end

    -- Rendering logic remains the same...
    vim.bo[top_buf].modifiable = true
    vim.api.nvim_buf_set_lines(top_buf, 0, -1, false, lines)
    for i = 0, #lines - 1 do
      if i == 1 then
        vim.api.nvim_buf_add_highlight(top_buf, -1, "TrackerHeader", i, 0, -1)
      elseif i == 2 then
        vim.api.nvim_buf_add_highlight(top_buf, -1, "SeparatorColor", i, 0, -1)
      elseif i > 2 then
        vim.api.nvim_buf_add_highlight(top_buf, -1, "WorkSessionGreen", i, 0, -1)
      end
    end
    vim.bo[top_buf].modifiable = false
  end

  -- 4. BUILD SUMMARY DATA (Bottom Window - Duration Included)
  local raw_data = get_sql_output(
    "SELECT strftime('%m/%d', start_time, 'unixepoch', 'localtime'), strftime('%w', start_time, 'unixepoch', 'localtime'), id, (end_time - start_time) FROM sessions ORDER BY start_time DESC;"
  )
  local project_map_res = get_sql_output("SELECT session_id, cwd FROM buffers;")

  local session_to_project = {}
  for line in project_map_res:gmatch("[^\r\n]+") do
    local p = vim.split(line, "|")
    if #p >= 2 then session_to_project[p[1]] = vim.fn.fnamemodify(p[2], ":h:t") end
  end

  local daily_agg, project_totals, ordered_keys = {}, {}, {}
  local days = { [0] = "Sun", [1] = "Mon", [2] = "Tue", [3] = "Wed", [4] = "Thu", [5] = "Fri", [6] = "Sat" }

  for line in raw_data:gmatch("[^\r\n]+") do
    local p = vim.split(line, "|")
    if #p >= 4 then
      local date, day_idx, sid, sec = p[1], tonumber(p[2]), p[3], tonumber(p[4]) or 0
      local root = session_to_project[sid] or "---"
      if root ~= "---" and root ~= "." and root ~= "" then
        local key = date .. "|" .. root
        if not daily_agg[key] then
          table.insert(ordered_keys, key)
          daily_agg[key] = { date = date, day = days[day_idx], root = root, time = 0 }
        end
        daily_agg[key].time = daily_agg[key].time + sec
        project_totals[root] = (project_totals[root] or 0) + sec
      end
    end
  end

  local bot_format = " %-7s | %-5s | %-25s | %-15s | %-15s"

  local summary_lines = {
    "",
    string.format(bot_format, "Date", "Day", "Project Root", "Daily", "Project Total"),
    string.rep("─", total_w),
  }

  for _, key in ipairs(ordered_keys) do
    local item = daily_agg[key]
    table.insert(
      summary_lines,
      string.format(
        bot_format,
        item.date,
        item.day,
        item.root,
        format_time(item.time),
        format_time(project_totals[item.root])
      )
    )
    line_to_data[#summary_lines] = { date = item.date, project_root = item.root }
  end

  vim.bo[bot_buf].modifiable = true
  vim.api.nvim_buf_set_lines(bot_buf, 0, -1, false, summary_lines)
  for i = 0, #summary_lines - 1 do
    if i == 1 then
      vim.api.nvim_buf_add_highlight(bot_buf, -1, "TrackerHeader", i, 0, -1)
    elseif i == 2 then
      vim.api.nvim_buf_add_highlight(bot_buf, -1, "SeparatorColor", i, 0, -1)
    elseif i > 2 then
      vim.api.nvim_buf_add_highlight(bot_buf, -1, "SummaryWhite", i, 0, -1)
    end
  end
  vim.bo[bot_buf].modifiable = false

  -- 5. CLEANUP & KEYMAPS
  local close = function()
    pcall(vim.api.nvim_win_close, top_win, true)
    pcall(vim.api.nvim_win_close, bot_win, true)
  end

  for _, i in ipairs({ { b = top_buf, w = top_win }, { b = bot_buf, w = bot_win } }) do
    vim.bo[i.b].buftype = "nofile"
    vim.wo[i.w].number, vim.wo[i.w].cursorline, vim.wo[i.w].wrap = false, true, false
    vim.keymap.set("n", "q", close, { buffer = i.b })
    vim.keymap.set("n", "sk", function() vim.api.nvim_set_current_win(top_win) end, { buffer = i.b })
    vim.keymap.set("n", "sj", function() vim.api.nvim_set_current_win(bot_win) end, { buffer = i.b })
  end

  refresh_ui()
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = bot_buf, callback = refresh_ui })
end

return {
  render = render,
  get_current_session_duration = get_current_session_duration,
  get_current_project_all_time_file_durations = get_current_project_all_time_file_durations,
  get_all_projects_durations = get_all_projects_durations,
  get_current_session_file_durations = get_current_session_file_durations,
  show_session_history = M.show_session_history,
}
