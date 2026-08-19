local TimeTracker = require("time-tracker/tracker").TimeTracker

local function tracker_with_buffer(count_result, rows)
  return {
    Buffer = {
      query = function()
        return {
          select = function()
            return {
              execute = function()
                return count_result
              end,
            }
          end,
        }
      end,
      all = function()
        return rows
      end,
    },
  }
end

describe("TimeTracker", function()
  local config = {
    data_file = "/tmp/time-tracker.sqlite",
    tracking_events = { "BufEnter" },
    tracking_timeout_seconds = 1,
  }

  before_each(function()
    os.remove(config.data_file)
  end)

  it("creates a new instance", function()
    local tracker = TimeTracker:new(config)
    expect(tracker.config).toBe(config)
  end)

  it("starts a session", function()
    local tracker = TimeTracker:new(config)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "/dev/null")
    tracker:start_session()
    expect(tracker.current_session).n.toBe(nil)
  end)

  it("loads empty roots when the persisted buffer count is zero", function()
    local tracker = tracker_with_buffer({ { count = 0 } }, nil)
    expect(TimeTracker.load_data(tracker)).toEqual({ roots = {} })
  end)

  it("converts persisted rows into full CWD and path intervals", function()
    local special_path = '/work/client/"quoted"|$(noop)%plugin.lua'
    local tracker = tracker_with_buffer({ { count = 3 } }, {
      {
        session_id = 1,
        cwd = "/work/client",
        path = special_path,
        start_time = 100,
        end_time = 200,
      },
      {
        session_id = 1,
        cwd = "/archive/client",
        path = "/archive/client/plugin.lua",
        start_time = 300,
        end_time = 450,
      },
      {
        session_id = 1,
        cwd = "/work/client",
        path = special_path,
        start_time = 500,
        end_time = 700,
      },
    })

    expect(TimeTracker.load_data(tracker)).toEqual({
      roots = {
        ["/archive/client"] = {
          ["/archive/client/plugin.lua"] = {
            { start = 300, ["end"] = 450 },
          },
        },
        ["/work/client"] = {
          [special_path] = {
            { start = 100, ["end"] = 200 },
            { start = 500, ["end"] = 700 },
          },
        },
      },
    })
  end)

  it("rejects nil and malformed persisted buffer counts", function()
    for _, count_result in ipairs({ false, {}, { {} }, { { count = "1" } } }) do
      local tracker = tracker_with_buffer(count_result == false and nil or count_result, {})
      expect(function()
        TimeTracker.load_data(tracker)
      end).toThrow("Failed to count persisted time-tracker buffers.")
    end
  end)

  it("rejects missing persisted rows after a positive count", function()
    local tracker = tracker_with_buffer({ { count = 1 } }, nil)
    expect(function()
      TimeTracker.load_data(tracker)
    end).toThrow("Failed to load persisted time-tracker buffers.")
  end)
end)
