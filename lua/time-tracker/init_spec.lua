local TimeTracker = require("time-tracker/tracker").TimeTracker

describe("time-tracker setup", function()
  local create_autocmd
  local create_user_command
  local new
  local time_tracker

  before_each(function()
    package.loaded["time-tracker"] = nil
    time_tracker = require("time-tracker")
    create_autocmd = vim.api.nvim_create_autocmd
    create_user_command = vim.api.nvim_create_user_command
    new = TimeTracker.new
  end)

  after_each(function()
    vim.api.nvim_create_autocmd = create_autocmd
    vim.api.nvim_create_user_command = create_user_command
    TimeTracker.new = new
    package.loaded["time-tracker"] = nil
  end)

  it("resolves a relative data file before constructing the tracker", function()
    local received_config
    TimeTracker.new = function(_, config)
      received_config = config
      return nil
    end

    time_tracker.setup({ data_file = "time-tracker-relative.sqlite" })

    expect(received_config.data_file).toBe(vim.fn.fnamemodify("time-tracker-relative.sqlite", ":p"))
  end)

  it("does not register autocmds after a permanent initialization failure", function()
    local autocmd_count = 0
    TimeTracker.new = function()
      return nil
    end
    vim.api.nvim_create_autocmd = function()
      autocmd_count = autocmd_count + 1
    end

    local ok, err = pcall(time_tracker.setup, { data_file = "/tmp/time-tracker.sqlite" })

    expect(ok and "" or tostring(err)).toBe("")
    expect(autocmd_count).toBe(0)
  end)

  it("registers recovery callbacks without repeating a failed initialization", function()
    local autocmd_count = 0
    local start_session_count = 0
    TimeTracker.new = function()
      local tracker = {
        start_session = function()
          start_session_count = start_session_count + 1
        end,
      }
      return tracker, false
    end
    vim.api.nvim_create_autocmd = function()
      autocmd_count = autocmd_count + 1
    end
    vim.api.nvim_create_user_command = function() end

    time_tracker.setup({ data_file = "/tmp/time-tracker.sqlite", tracking_events = { "BufEnter" } })

    expect(start_session_count).toBe(0)
    expect(autocmd_count).toBe(2)
  end)

  it("rejects invalid data file paths before opening SQLite", function()
    local new_count = 0
    TimeTracker.new = function()
      new_count = new_count + 1
    end

    for _, data_file in ipairs({ "/tmp", vim.fn.tempname() .. "/time-tracker.sqlite" }) do
      expect(function()
        time_tracker.setup({ data_file = data_file })
      end).toThrow("Invalid data file path")
    end
    expect(new_count).toBe(0)
  end)
end)
