local TimeTracker = require("time-tracker/tracker").TimeTracker
local sqlite = require("sqlite")

local function remove_database(path)
  os.remove(path)
  os.remove(path .. "-journal")
  os.remove(path .. "-wal")
  os.remove(path .. "-shm")
end

local function read_database(path, fn)
  local db = sqlite.open(path)
  local ok, result = pcall(fn, db)
  db:close()
  if not ok then error(result, 0) end
  return result
end

local function tracker_with_buffer(count_result, rows)
  return {
    execute_with_retry = function(_, fn)
      local ok, result = pcall(fn)
      return ok, result
    end,
    is_retryable_database_error = TimeTracker.is_retryable_database_error,
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
  local replacement_path = config.data_file .. ".replacement"

  before_each(function()
    remove_database(config.data_file)
    remove_database(replacement_path)
  end)

  after_each(function()
    remove_database(config.data_file)
    remove_database(replacement_path)
  end)

  it("creates a new instance", function()
    local tracker, initialized = TimeTracker:new(config)
    expect(tracker.config).toBe(config)
    expect(initialized).toBe(true)
  end)

  it("does not return an instance after a permanent initialization failure", function()
    local execute_with_retry = TimeTracker.execute_with_retry
    TimeTracker.execute_with_retry = function()
      return false, "Failed to spawn SQLite process. Is sqlite3 installed and in your PATH?"
    end

    local tracker, initialized = TimeTracker:new(config)
    TimeTracker.execute_with_retry = execute_with_retry

    expect(tracker).toBe(nil)
    expect(initialized).toBe(false)
  end)

  it("returns an instance after a retryable initialization failure", function()
    local execute_with_retry = TimeTracker.execute_with_retry
    TimeTracker.execute_with_retry = function()
      return false, "SQLite query timed out after 1000 ms"
    end

    local tracker, initialized = TimeTracker:new(config)
    TimeTracker.execute_with_retry = execute_with_retry

    expect(tracker).n.toBe(nil)
    expect(initialized).toBe(false)
  end)

  it("defers contention recovery to a later activity event", function()
    for _, message in ipairs({ "SQLite query timed out after 1000 ms", "SQLite error: database is locked" }) do
      local attempts = 0
      local tracker = {
        execute_database_operation = function()
          attempts = attempts + 1
          error(message)
        end,
        is_retryable_database_error = TimeTracker.is_retryable_database_error,
      }

      local ok = TimeTracker.execute_with_retry(tracker, function() end)

      expect(ok).toBe(false)
      expect(attempts).toBe(1)
    end
  end)

  it("starts a session", function()
    local tracker = TimeTracker:new(config)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "/dev/null")
    tracker:start_session()
    expect(tracker.current_session).n.toBe(nil)
  end)

  it("uses DELETE journal mode without persistent sidecar files", function()
    local tracker = TimeTracker:new(config)
    tracker:start_session()
    tracker:load_data()

    local journal_mode = read_database(config.data_file, function(db)
      return db:sql("PRAGMA journal_mode")
    end)
    expect(journal_mode[1].journal_mode).toBe("delete")
    expect(vim.loop.fs_stat(config.data_file .. "-journal")).toBe(nil)
    expect(vim.loop.fs_stat(config.data_file .. "-wal")).toBe(nil)
    expect(vim.loop.fs_stat(config.data_file .. "-shm")).toBe(nil)
  end)

  it("uses a database that replaces the closed database between operations", function()
    local tracker = TimeTracker:new(config)
    tracker:start_session()

    local replacement_config = vim.tbl_extend("force", config, { data_file = replacement_path })
    local replacement_tracker = TimeTracker:new(replacement_config)
    replacement_tracker:start_session()

    assert(os.rename(replacement_path, config.data_file))
    tracker:start_session()

    local sessions = read_database(config.data_file, function(db)
      return db:sql("SELECT * FROM sessions")
    end)
    expect(#sessions).toBe(2)
    expect(vim.loop.fs_stat(config.data_file .. "-journal")).toBe(nil)
    expect(vim.loop.fs_stat(config.data_file .. "-wal")).toBe(nil)
    expect(vim.loop.fs_stat(config.data_file .. "-shm")).toBe(nil)
  end)

  it("retries when the database is replaced during an operation", function()
    local tracker = TimeTracker:new(config)
    local replacement_config = vim.tbl_extend("force", config, { data_file = replacement_path })
    local replacement_tracker = TimeTracker:new(replacement_config)
    replacement_tracker:start_session()

    local replaced = false
    local create_session = tracker.Session.create
    tracker.Session.create = function(model, data)
      if not replaced then
        replaced = true
        assert(os.rename(replacement_path, config.data_file))
      end
      return create_session(model, data)
    end

    local ok, err = pcall(function()
      tracker:start_session()
    end)
    tracker.Session.create = create_session
    if not ok then error(err, 0) end

    local sessions = read_database(config.data_file, function(db)
      return db:sql("SELECT * FROM sessions")
    end)
    expect(#sessions).toBe(2)
    expect(tracker.current_session.id).toBe(2)
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
