local t = require("testing")
local ui = require("time-tracker/ui")

-- Files:
-- /foo/bar.txt - 50 (stored) + 100 (current session) = 150
-- /foo/baz.txt - 50 (stored) + 100 (current buffer) = 150
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

describe("ui", function()
  local localtime = t.spy(vim.fn, "localtime")
  localtime.mockReturnValue(400)

  it("returns file durations for current session", function()
    local durations = ui.get_current_session_file_durations(tracker)
    expect(durations["/foo/bar.txt"]).toBe(100)
    expect(durations["/foo/baz.txt"]).toBe(100)
  end)

  it("returns total duration for current session", function()
    local durations = ui.get_current_session_file_durations(tracker)
    local total_duration = ui.get_current_session_duration(durations)
    expect(total_duration).toBe(200)
  end)

  it("returns all-time file durations for current project", function()
    local current_session_durations = ui.get_current_session_file_durations(tracker)
    local data = tracker:load_data()
    local all_time_durations = ui.get_current_project_all_time_file_durations(data, "/foo", current_session_durations)
    expect(all_time_durations["/foo/bar.txt"]).toBe(150)
    expect(all_time_durations["/foo/baz.txt"]).toBe(150)
  end)

  it("returns durations for all projects", function()
    local data = tracker:load_data()
    local durations = ui.get_all_projects_durations(tracker, data)
    expect(durations["/foo"]).toBe(300)
    expect(durations["/other"]).toBe(100)
  end)
end)
