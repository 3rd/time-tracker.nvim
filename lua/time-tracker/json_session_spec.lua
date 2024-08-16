local JsonSession = require("time-tracker/json_session").JsonSession

describe("JsonSession", function()
  local config = {
    data_file = "/tmp/time-tracker.json",
    tracking_events = { "BufEnter" },
    tracking_timeout_seconds = 1,
  }

  before_each(function()
    os.remove(config.data_file)
  end)

  it("creates a new instance", function()
    local tracker = JsonSession:new(config)
    expect(tracker.config).toBe(config)
  end)

  it("starts a session", function()
    local tracker = JsonSession:new(config)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "/dev/null")
    tracker:start_session(buf)
    expect(tracker.current_session).n.toBe(nil)
  end)
end)
