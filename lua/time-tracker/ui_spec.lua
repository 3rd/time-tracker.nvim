local t = require("testing")
local ui = require("time-tracker/ui")

local function local_timestamp(year, month, day, hour, minute, second)
  local timestamp = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour or 0,
    min = minute or 0,
    sec = second or 0,
    isdst = nil,
  })
  if not timestamp then error("Failed to create local test timestamp.") end
  return timestamp
end

local function local_day_time(timestamp, day_offset, hour, minute)
  local date = os.date("*t", timestamp)
  date.day = date.day + day_offset
  date.hour = hour
  date.min = minute or 0
  date.sec = 0
  date.isdst = nil
  local shifted = os.time(date)
  if not shifted then error("Failed to shift local test timestamp.") end
  return shifted
end

local function sorted_intervals(snapshot)
  local intervals = vim.deepcopy(snapshot.intervals)
  table.sort(intervals, function(a, b)
    if a.cwd ~= b.cwd then return a.cwd < b.cwd end
    if a.path ~= b.path then return a.path < b.path end
    return a.start < b.start
  end)
  return intervals
end

local function get_history_windows()
  local windows = { count = 0 }
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      windows.count = windows.count + 1
      local buf = vim.api.nvim_win_get_buf(win)
      local heading = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if heading == "**Work sessions**" then windows.work = win end
      if heading and heading:find("**Weekly summary**", 1, true) == 1 then windows.summary = win end
    end
  end
  return windows
end

local function close_history_windows()
  local windows = get_history_windows()
  for _, win in ipairs({ windows.work, windows.summary }) do
    if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  end
end

local function with_history_modal(columns, lines, captured_now, tracker, fn)
  local previous_columns = vim.o.columns
  local previous_lines = vim.o.lines
  local previous_win = vim.api.nvim_get_current_win()
  local localtime = t.spy(vim.fn, "localtime")
  localtime.mockReturnValue(captured_now)

  local ok, err = pcall(function()
    vim.o.columns = columns
    vim.o.lines = lines
    ui.show_session_history(tracker)
    local windows = get_history_windows()
    if not windows.work or not windows.summary then error("History floats did not open.") end
    fn(windows)
  end)

  close_history_windows()
  if vim.api.nvim_win_is_valid(previous_win) then vim.api.nvim_set_current_win(previous_win) end
  vim.o.columns = previous_columns
  vim.o.lines = previous_lines
  localtime.destroy()
  return ok, err
end

local function invoke_mapping(win, lhs)
  vim.api.nvim_set_current_win(win)
  local mapping = vim.fn.maparg(lhs, "n", false, true)
  if type(mapping) ~= "table" or type(mapping.callback) ~= "function" then
    error("History mapping is not callable: " .. lhs)
  end
  mapping.callback()
end

local function buffer_lines(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function lines_contain(lines, text)
  for _, line in ipairs(lines) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function lines_fit(win)
  local width = vim.api.nvim_win_get_width(win)
  for _, line in ipairs(buffer_lines(win)) do
    if vim.fn.strdisplaywidth(line) > width then return false end
  end
  return true
end

local function rounded_border(config)
  local characters = {}
  for _, part in ipairs(config.border) do
    table.insert(characters, type(part) == "table" and part[1] or part)
  end
  return characters
end

local function expect_history_geometry(windows, width, top_height, summary_height)
  local work_config = vim.api.nvim_win_get_config(windows.work)
  local summary_config = vim.api.nvim_win_get_config(windows.summary)
  local border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }

  expect(work_config.title).toBe(nil)
  expect(summary_config.title).toBe(nil)
  expect(rounded_border(work_config)).toEqual(border)
  expect(rounded_border(summary_config)).toEqual(border)
  expect(work_config.width).toBe(width)
  expect(summary_config.width).toBe(width)
  expect(work_config.height).toBe(top_height)
  expect(summary_config.height).toBe(summary_height)
  expect(summary_config.row).toBe(work_config.row + top_height + 2)
end

local function resize_history(columns, lines)
  vim.o.columns = columns
  vim.o.lines = lines
  vim.api.nvim_exec_autocmds("VimResized", {})
end

local function window_topline(win)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
end

local function cursor_is_visible(win)
  local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
  local topline = window_topline(win)
  return topline <= cursor_line and cursor_line < topline + vim.api.nvim_win_get_height(win)
end

local function modal_tracker(captured_now, empty)
  local current_week_start = ui.get_history_week_bounds(captured_now, 0)
  local older_week_start = ui.get_history_week_bounds(captured_now, 1)
  local data = { roots = {} }

  if not empty then
    data.roots = {
      ["/alpha/project"] = {
        ["/alpha/project/main.lua"] = {
          {
            start = local_day_time(current_week_start, 1, 9),
            ["end"] = local_day_time(current_week_start, 1, 10),
          },
        },
        ["/alpha/project/second.lua"] = {
          {
            start = local_day_time(current_week_start, 2, 10),
            ["end"] = local_day_time(current_week_start, 2, 10, 30),
          },
        },
      },
      ["/beta/project"] = {
        ["/beta/project/older.lua"] = {
          {
            start = local_day_time(older_week_start, 2, 13),
            ["end"] = local_day_time(older_week_start, 2, 15),
          },
        },
      },
    }
  end

  return {
    load_calls = 0,
    load_data = function(self)
      self.load_calls = self.load_calls + 1
      return data
    end,
  }
end

local tracker = {
  current_session = {
    buffers = {
      ["/foo"] = {
        ["/foo/bar.txt"] = {
          { start = 100, ["end"] = 200 },
        },
      },
    },
  },
  current_buffer = {
    cwd = "/foo",
    path = "/foo/baz.txt",
    start = 300,
  },
  load_data = function()
    return {
      roots = {
        ["/foo"] = {
          ["/foo/bar.txt"] = {
            { start = 50, ["end"] = 100 },
          },
          ["/foo/baz.txt"] = {
            { start = 150, ["end"] = 200 },
          },
        },
        ["/other"] = {
          ["/other/file.txt"] = {
            { start = 0, ["end"] = 100 },
          },
        },
      },
    }
  end,
}

local localtime = t.spy(vim.fn, "localtime")
localtime.mockReturnValue(400)

describe("ui", function()
  it("returns file durations for current session", function()
    local durations = ui.get_current_session_file_durations(tracker)
    expect(durations["/foo/bar.txt"]).toBe(100)
    expect(durations["/foo/baz.txt"]).toBe(100)
  end)

  it("returns total duration for current session", function()
    local durations = ui.get_current_session_file_durations(tracker)
    expect(ui.get_current_session_duration(durations)).toBe(200)
  end)

  it("returns all-time file durations for current project", function()
    local current_session_durations = ui.get_current_session_file_durations(tracker)
    local durations =
      ui.get_current_project_all_time_file_durations(tracker:load_data(), "/foo", current_session_durations)
    expect(durations["/foo/bar.txt"]).toBe(150)
    expect(durations["/foo/baz.txt"]).toBe(150)
  end)

  it("returns durations for all projects", function()
    local durations = ui.get_all_projects_durations(tracker, tracker:load_data())
    expect(durations["/foo"]).toBe(300)
    expect(durations["/other"]).toBe(100)
  end)
end)

localtime.destroy()

describe("history data", function()
  it("preserves full paths and includes one active interval exactly once", function()
    local captured_now = local_timestamp(2026, 1, 7, 12)
    local special_path = '/work/client/"quote"|$(touch nope)%done.lua'
    local snapshot = ui.build_history_snapshot({
      roots = {
        ["/archive/client"] = {
          ["/archive/client/same.lua"] = {
            { start = captured_now - 600, ["end"] = captured_now - 300 },
          },
        },
        ["/work/client"] = {
          [special_path] = {
            { start = captured_now - 1200, ["end"] = captured_now - 900 },
          },
        },
      },
    }, { buffers = {} }, {
      cwd = "/work/client",
      path = special_path,
      start = captured_now - 120,
    }, captured_now)

    expect(sorted_intervals(snapshot)).toEqual({
      {
        cwd = "/archive/client",
        path = "/archive/client/same.lua",
        start = captured_now - 600,
        ["end"] = captured_now - 300,
      },
      {
        cwd = "/work/client",
        path = special_path,
        start = captured_now - 1200,
        ["end"] = captured_now - 900,
      },
      {
        cwd = "/work/client",
        path = special_path,
        start = captured_now - 120,
        ["end"] = captured_now,
      },
    })
    expect(snapshot.project_totals).toEqual({
      ["/archive/client"] = 300,
      ["/work/client"] = 420,
    })
  end)

  it("ignores invalid records while preserving valid persisted data", function()
    local valid_start = local_timestamp(2026, 2, 2, 9)
    local valid_end = local_timestamp(2026, 2, 2, 10)
    local data = {
      roots = {
        ["/valid"] = {
          ["/valid/main.lua"] = {
            { start = valid_start, ["end"] = valid_end },
            { ["end"] = valid_end },
            { start = valid_start },
            { start = "bad", ["end"] = valid_end },
            { start = valid_end, ["end"] = valid_start },
            { start = valid_start, ["end"] = valid_start },
            "bad record",
          },
          ["/valid/not-a-list.lua"] = "bad intervals",
          [7] = { { start = valid_start, ["end"] = valid_end } },
        },
        ["/bad-root"] = "bad root",
        [9] = {
          ["/invalid-cwd.lua"] = { { start = valid_start, ["end"] = valid_end } },
        },
      },
    }
    local invalid_live_buffers = {
      { session = nil, buffer = { cwd = "/live", path = "/live/main.lua", start = valid_start } },
      { session = {}, buffer = { cwd = "/live", path = "/live/main.lua", start = valid_end + 1 } },
      { session = {}, buffer = { cwd = 7, path = "/live/main.lua", start = valid_start } },
      { session = {}, buffer = { cwd = "/live", path = 7, start = valid_start } },
      { session = {}, buffer = { cwd = "/live", path = "/live/main.lua" } },
      { session = {}, buffer = { cwd = "/live", path = "/live/main.lua", start = valid_end } },
    }

    for _, item in ipairs(invalid_live_buffers) do
      local snapshot = ui.build_history_snapshot(data, item.session, item.buffer, valid_end)
      expect(snapshot.intervals).toEqual({
        { cwd = "/valid", path = "/valid/main.lua", start = valid_start, ["end"] = valid_end },
      })
      expect(snapshot.project_totals).toEqual({ ["/valid"] = valid_end - valid_start })
    end
  end)

  it("keeps one session's persisted intervals attributed to separate CWDs", function()
    local first_start = local_timestamp(2026, 3, 4, 9)
    local second_start = local_timestamp(2026, 3, 4, 10)
    local snapshot = ui.build_history_snapshot({
      roots = {
        ["/clients/east/app"] = {
          ["/clients/east/app/main.lua"] = { { start = first_start, ["end"] = first_start + 300 } },
        },
        ["/archives/east/app"] = {
          ["/archives/east/app/main.lua"] = { { start = second_start, ["end"] = second_start + 600 } },
        },
      },
    }, { buffers = {} }, nil, second_start + 600)

    expect(snapshot.project_totals).toEqual({
      ["/archives/east/app"] = 600,
      ["/clients/east/app"] = 300,
    })
    expect(#snapshot.intervals).toBe(2)
  end)

  it("returns Monday-to-Monday week bounds with calendar offsets", function()
    local timestamp = local_timestamp(2026, 1, 7, 15, 30)
    local current_start, current_end = ui.get_history_week_bounds(timestamp, 0)
    local previous_start, previous_end = ui.get_history_week_bounds(timestamp, 1)

    expect(os.date("%Y-%m-%d %H:%M:%S", current_start)).toBe("2026-01-05 00:00:00")
    expect(os.date("%Y-%m-%d %H:%M:%S", current_end)).toBe("2026-01-12 00:00:00")
    expect(os.date("%Y-%m-%d %H:%M:%S", previous_start)).toBe("2025-12-29 00:00:00")
    expect(previous_end).toBe(current_start)
    expect(function()
      ui.get_history_week_bounds(timestamp, -1)
    end).toThrow("History week offset must be a non-negative integer.")
    expect(function()
      ui.get_history_week_bounds(timestamp, 0.5)
    end).toThrow("History week offset must be a non-negative integer.")
  end)

  it("splits and clips summaries by local days and exact full CWD", function()
    local week_start = local_timestamp(2026, 1, 5)
    local week_end = local_timestamp(2026, 1, 12)
    local snapshot = ui.build_history_snapshot({
      roots = {
        ["/work/east/app"] = {
          ["/work/east/app/main.txt"] = {
            { start = local_timestamp(2026, 1, 4, 23, 30), ["end"] = local_timestamp(2026, 1, 5, 0, 30) },
            { start = local_timestamp(2026, 1, 6, 23, 30), ["end"] = local_timestamp(2026, 1, 7, 0, 45) },
            { start = local_timestamp(2026, 1, 11, 23, 30), ["end"] = local_timestamp(2026, 1, 12, 0, 30) },
          },
        },
        ["/archive/east/app"] = {
          ["/archive/east/app/plugin.lua"] = {
            { start = local_timestamp(2026, 1, 5, 11), ["end"] = local_timestamp(2026, 1, 5, 11, 10) },
          },
        },
      },
    }, nil, nil, week_end)
    local summaries = ui.get_history_week_summary(snapshot, week_start, week_end)

    expect(vim.tbl_map(function(summary)
      return { summary.date, summary.cwd, summary.daily_duration }
    end, summaries)).toEqual({
      { "2026-01-11", "/work/east/app", 1800 },
      { "2026-01-07", "/work/east/app", 2700 },
      { "2026-01-06", "/work/east/app", 1800 },
      { "2026-01-05", "/archive/east/app", 600 },
      { "2026-01-05", "/work/east/app", 1800 },
    })
    expect(summaries[1].project_total).toBe(11700)
    expect(summaries[4].project_total).toBe(600)
  end)

  it("keeps Project Total all-time while weekly values are clipped", function()
    local current_week_start = local_timestamp(2026, 1, 12)
    local current_week_end = local_timestamp(2026, 1, 19)
    local older_week_start = local_timestamp(2026, 1, 5)
    local snapshot = ui.build_history_snapshot({
      roots = {
        ["/project"] = {
          ["/project/main.lua"] = {
            { start = local_timestamp(2026, 1, 1, 9), ["end"] = local_timestamp(2026, 1, 1, 10) },
            { start = local_timestamp(2026, 1, 11, 23, 30), ["end"] = local_timestamp(2026, 1, 12, 0, 45) },
          },
        },
      },
    }, nil, nil, current_week_end)
    local current = ui.get_history_week_summary(snapshot, current_week_start, current_week_end)
    local older = ui.get_history_week_summary(snapshot, older_week_start, current_week_start)

    expect(current[1].daily_duration).toBe(2700)
    expect(older[1].daily_duration).toBe(1800)
    expect(current[1].project_total).toBe(8100)
    expect(older[1].project_total).toBe(8100)
  end)

  it("filters and sorts work sessions within the exact range", function()
    local range_start = local_timestamp(2026, 1, 6, 9)
    local range_end = local_timestamp(2026, 1, 6, 12)
    local snapshot = {
      intervals = {
        {
          cwd = "/b",
          path = "/b/z.lua",
          start = local_timestamp(2026, 1, 6, 11),
          ["end"] = local_timestamp(2026, 1, 6, 13),
        },
        {
          cwd = "/a",
          path = "/a/b.lua",
          start = local_timestamp(2026, 1, 6, 10),
          ["end"] = local_timestamp(2026, 1, 6, 10, 30),
        },
        {
          cwd = "/a",
          path = "/a/a.lua",
          start = local_timestamp(2026, 1, 6, 10),
          ["end"] = local_timestamp(2026, 1, 6, 10, 30),
        },
        {
          cwd = "/b",
          path = "/b/a.lua",
          start = local_timestamp(2026, 1, 6, 10),
          ["end"] = local_timestamp(2026, 1, 6, 10, 30),
        },
        {
          cwd = "/outside",
          path = "/outside/old.lua",
          start = local_timestamp(2026, 1, 5, 8),
          ["end"] = local_timestamp(2026, 1, 5, 9),
        },
        { cwd = "/outside", path = "/outside/new.lua", start = range_end, ["end"] = range_end + 600 },
      },
      project_totals = {},
    }
    local sessions = ui.get_history_work_sessions(snapshot, range_start, range_end)
    local filtered = ui.get_history_work_sessions(snapshot, range_start, range_end, "/a")

    expect(vim.tbl_map(function(session)
      return { session.cwd, session.path, session.start, session["end"] }
    end, sessions)).toEqual({
      { "/b", "/b/z.lua", local_timestamp(2026, 1, 6, 11), range_end },
      { "/a", "/a/a.lua", local_timestamp(2026, 1, 6, 10), local_timestamp(2026, 1, 6, 10, 30) },
      { "/a", "/a/b.lua", local_timestamp(2026, 1, 6, 10), local_timestamp(2026, 1, 6, 10, 30) },
      { "/b", "/b/a.lua", local_timestamp(2026, 1, 6, 10), local_timestamp(2026, 1, 6, 10, 30) },
    })
    expect(vim.tbl_map(function(session)
      return session.path
    end, filtered)).toEqual({ "/a/a.lua", "/a/b.lua" })
  end)
end)

describe("history modal", function()
  local captured_now = local_timestamp(2026, 1, 7, 12)

  it("opens independent untitled Markdown panes with synchronized selection", function()
    local history_tracker = modal_tracker(captured_now)
    local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
      local summary_lines = buffer_lines(windows.summary)
      local work_lines = buffer_lines(windows.work)
      local summary_buf = vim.api.nvim_win_get_buf(windows.summary)
      local work_buf = vim.api.nvim_win_get_buf(windows.work)

      expect(windows.count).toBe(2)
      expect(summary_buf).n.toBe(work_buf)
      expect_history_geometry(windows, 80, 15, 13)
      expect(vim.api.nvim_get_current_win()).toBe(windows.summary)
      expect(vim.api.nvim_win_get_cursor(windows.summary)[1]).toBe(3)
      expect(vim.wo[windows.work].cursorline).toBe(false)
      expect(vim.wo[windows.summary].cursorline).toBe(true)
      expect(work_lines[1]).toBe("**Work sessions**")
      expect(summary_lines[1]).toBe("**Weekly summary** | (H) Older (L) Newer | `Current week`")
      expect(summary_lines[3]).toMatch("- 2026-01-07 Wed · `/alpha/project`")
      expect(summary_lines[3]).toMatch("daily 00:30:00 · total 01:30:00")
      expect(work_lines[3]).toBe("- 10:00 AM · `/alpha/project` · `second.lua`")
      for _, buf in ipairs({ summary_buf, work_buf }) do
        expect(vim.bo[buf].buftype).toBe("nofile")
        expect(vim.bo[buf].bufhidden).toBe("wipe")
        expect(vim.bo[buf].filetype).toBe("markdown")
        expect(vim.bo[buf].swapfile).toBe(false)
        expect(vim.bo[buf].modifiable).toBe(false)
      end
      expect(lines_fit(windows.work)).toBe(true)
      expect(lines_fit(windows.summary)).toBe(true)
      expect(history_tracker.load_calls).toBe(1)
    end)
    expect(ok and "" or tostring(err)).toBe("")
  end)

  it("keeps selected Markdown details through responsive fixed-height layouts", function()
    local history_tracker = modal_tracker(captured_now)
    local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
      local summary_buf = vim.api.nvim_win_get_buf(windows.summary)
      vim.api.nvim_win_set_cursor(windows.summary, { 4, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = summary_buf })
      local wide_summary = buffer_lines(windows.summary)
      local wide_work = buffer_lines(windows.work)

      expect_history_geometry(windows, 80, 15, 13)
      expect(lines_contain(wide_work, "main.lua")).toBe(true)
      expect(window_topline(windows.work)).toBe(1)
      expect(window_topline(windows.summary)).toBe(1)

      resize_history(60, 20)
      expect_history_geometry(windows, 48, 6, 6)
      expect(buffer_lines(windows.summary)).n.toEqual(wide_summary)
      expect(buffer_lines(windows.summary)[1]).toBe("**Weekly summary** | H/L | `Current week`")
      expect(vim.api.nvim_win_get_cursor(windows.summary)[1]).toBe(4)
      expect(lines_contain(buffer_lines(windows.work), "main.lua")).toBe(true)
      expect(window_topline(windows.work)).toBe(1)
      expect(window_topline(windows.summary)).toBe(1)
      expect(cursor_is_visible(windows.summary)).toBe(true)
      expect(lines_fit(windows.work)).toBe(true)
      expect(lines_fit(windows.summary)).toBe(true)

      resize_history(120, 40)
      expect_history_geometry(windows, 96, 15, 13)
      expect(buffer_lines(windows.summary)).n.toEqual(wide_summary)
      expect(buffer_lines(windows.work)).n.toEqual(wide_work)
      expect(vim.api.nvim_win_get_cursor(windows.summary)[1]).toBe(4)
      expect(window_topline(windows.work)).toBe(1)
      expect(window_topline(windows.summary)).toBe(1)

      resize_history(46, 13)
      expect_history_geometry(windows, 36, 3, 3)
      expect(buffer_lines(windows.summary)).n.toEqual(wide_summary)
      expect(buffer_lines(windows.summary)[1]).toBe("**Weekly summary** | H/L | `…t week`")
      expect(vim.api.nvim_win_get_cursor(windows.summary)[1]).toBe(4)
      expect(lines_contain(buffer_lines(windows.work), "main.lua")).toBe(true)
      expect(window_topline(windows.work)).toBe(1)
      expect(cursor_is_visible(windows.summary)).toBe(true)
      expect(lines_fit(windows.work)).toBe(true)
      expect(lines_fit(windows.summary)).toBe(true)
      expect(vim.api.nvim_get_current_win()).toBe(windows.summary)
      expect(history_tracker.load_calls).toBe(1)
    end)
    expect(ok and "" or tostring(err)).toBe("")
  end)

  it("changes weeks and follows arbitrary window navigation mappings without reloading", function()
    local history_tracker = modal_tracker(captured_now)
    local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
      local current_summary = buffer_lines(windows.summary)
      local current_work = buffer_lines(windows.work)
      local summary_buf = vim.api.nvim_win_get_buf(windows.summary)

      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = summary_buf })
      invoke_mapping(windows.summary, "L")
      expect(buffer_lines(windows.summary)).toEqual(current_summary)
      expect(buffer_lines(windows.work)).toEqual(current_work)

      invoke_mapping(windows.summary, "H")
      expect(buffer_lines(windows.summary)).n.toEqual(current_summary)
      expect(buffer_lines(windows.work)).n.toEqual(current_work)
      expect(buffer_lines(windows.summary)[1]).toMatch("`1 week ago`")
      expect(lines_contain(buffer_lines(windows.summary), "/beta/project")).toBe(true)
      expect(lines_contain(buffer_lines(windows.work), "older.lua")).toBe(true)

      vim.api.nvim_win_set_cursor(windows.summary, { 1, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = summary_buf })
      expect(lines_contain(buffer_lines(windows.work), "older.lua")).toBe(true)
      expect(lines_contain(buffer_lines(windows.work), "main.lua")).toBe(false)

      invoke_mapping(windows.summary, "L")
      expect(buffer_lines(windows.summary)[1]).toMatch("`Current week`")
      expect(lines_contain(buffer_lines(windows.summary), "/alpha/project")).toBe(true)
      expect(lines_contain(buffer_lines(windows.work), "second.lua")).toBe(true)

      vim.keymap.set("n", "<F6>", function()
        vim.cmd.wincmd("k")
      end, { buffer = summary_buf })
      vim.api.nvim_feedkeys(vim.keycode("<F6>"), "xt", false)
      expect(vim.api.nvim_get_current_win()).toBe(windows.work)
      vim.keymap.set("n", "<F7>", function()
        vim.cmd.wincmd("j")
      end, { buffer = vim.api.nvim_win_get_buf(windows.work) })
      vim.api.nvim_feedkeys(vim.keycode("<F7>"), "xt", false)
      expect(vim.api.nvim_get_current_win()).toBe(windows.summary)
      expect(history_tracker.load_calls).toBe(1)
    end)
    expect(ok and "" or tostring(err)).toBe("")
  end)

  it("closes both panes with q", function()
    local history_tracker = modal_tracker(captured_now)
    local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
      invoke_mapping(windows.summary, "q")
      expect(vim.api.nvim_win_is_valid(windows.work)).toBe(false)
      expect(vim.api.nvim_win_is_valid(windows.summary)).toBe(false)
    end)
    expect(ok and "" or tostring(err)).toBe("")
  end)

  it("closes the pair when either float closes", function()
    for _, target in ipairs({ "work", "summary" }) do
      local history_tracker = modal_tracker(captured_now)
      local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
        vim.api.nvim_win_close(windows[target], true)
        expect(vim.api.nvim_win_is_valid(windows.work)).toBe(false)
        expect(vim.api.nvim_win_is_valid(windows.summary)).toBe(false)
      end)
      expect(ok and "" or tostring(err)).toBe("")
    end
  end)

  it("notifies without opening floats below the minimum size", function()
    local previous_columns = vim.o.columns
    local previous_lines = vim.o.lines
    local notify = t.spy(vim, "notify")
    notify.mockImplementation(function() end)
    local history_tracker = modal_tracker(captured_now)
    local ok, err = pcall(function()
      vim.o.columns = 45
      vim.o.lines = 12
      ui.show_session_history(history_tracker)
    end)
    local calls = vim.deepcopy(notify.calls)

    close_history_windows()
    vim.o.columns = previous_columns
    vim.o.lines = previous_lines
    notify.destroy()

    expect(ok and "" or tostring(err)).toBe("")
    expect(#calls).toBe(1)
    expect(calls[1].args[1]).toBe("TimeTracker: History needs at least 46 columns and 13 lines.")
    expect(calls[1].args[2]).toBe(vim.log.levels.WARN)
    expect(get_history_windows().count).toBe(0)
    expect(history_tracker.load_calls).toBe(0)
  end)

  it("shows Markdown empty states in both panes", function()
    local history_tracker = modal_tracker(captured_now, true)
    local ok, err = with_history_modal(100, 40, captured_now, history_tracker, function(windows)
      expect(buffer_lines(windows.work)).toEqual({
        "**Work sessions**",
        string.rep("─", 80),
        "No work sessions for this week.",
      })
      expect(buffer_lines(windows.summary)).toEqual({
        "**Weekly summary** | (H) Older (L) Newer | `Current week`",
        string.rep("─", 80),
        "No tracked time for this week.",
      })
      expect(vim.api.nvim_win_get_cursor(windows.summary)[1]).toBe(3)
      expect(history_tracker.load_calls).toBe(1)
    end)
    expect(ok and "" or tostring(err)).toBe("")
  end)
end)
