local orm = require("sqlite.orm")
local sqlite = require("sqlite")
local utils = require("time-tracker/utils")

local MAX_IMMEDIATE_DATABASE_ATTEMPTS = 5
local DATABASE_BUSY_TIMEOUT_MS = 250
local DATABASE_OPERATION_TIMEOUT_MS = 1000
local DATABASE_REPLACED_ERROR = "TimeTracker database file was replaced during an operation."

local database_identity = function(path)
  local stat = vim.loop.fs_stat(path)
  if not stat or stat.ino == nil then return nil end
  return tostring(stat.dev) .. ":" .. tostring(stat.ino)
end

local close_database = function(db)
  if not db or not db.handle then return end
  pcall(function()
    db:close()
  end)
end

local is_database_contention_error = function(err)
  local err_str = tostring(err):lower()
  return err_str:find("sqlite query timed out", 1, true) ~= nil
    or err_str:find("locked", 1, true) ~= nil
    or err_str:find("busy", 1, true) ~= nil
end

---@type TimeTracker
local TimeTracker = {
  --- @type Config
  config = nil,
  current_buffer = nil,
  current_session = nil,
  Session = nil,
  Buffer = nil,

  new = function(self, config)
    local tracker = {
      config = config,
    }
    setmetatable(tracker, self)
    self.__index = self

    tracker:define_models()
    local ok, err = tracker:execute_with_retry(function() end)
    if ok then return tracker, true end

    vim.notify("TimeTracker: Failed to initialize the database. Error: " .. tostring(err), vim.log.levels.ERROR)
    if not tracker:is_retryable_database_error(err) then return nil, false end
    return tracker, false
  end,

  define_models = function(self)
    self.Session = orm.define("sessions", {
      id = orm.integer({ primary_key = true, auto_increment = true }),
      start_time = orm.integer({ not_null = true }),
      end_time = orm.integer({ not_null = true }),
    })

    self.Buffer = orm.define("buffers", {
      id = orm.integer({ primary_key = true, auto_increment = true }),
      session_id = orm.integer({ not_null = true }),
      cwd = orm.text({ not_null = true }),
      path = orm.text({ not_null = true }),
      start_time = orm.integer({ not_null = true }),
      end_time = orm.integer({ not_null = true }),
    })
  end,

  open_database = function(self)
    local db = sqlite.open(self.config.data_file, { timeout = DATABASE_OPERATION_TIMEOUT_MS })
    local ok, err = pcall(function()
      db:sql("PRAGMA busy_timeout=" .. DATABASE_BUSY_TIMEOUT_MS)
      db:sql("PRAGMA journal_mode=DELETE")
      self.Session:connect(db)
      self.Buffer:connect(db)
    end)
    if ok then return db end

    close_database(db)
    error(err, 0)
  end,

  execute_database_operation = function(self, fn)
    local db
    local identity_before_open = database_identity(self.config.data_file)
    local ok, result = pcall(function()
      db = self:open_database()
      local opened_identity = database_identity(self.config.data_file)
      if (identity_before_open or opened_identity) and identity_before_open ~= opened_identity then
        error(DATABASE_REPLACED_ERROR, 0)
      end

      local operation_result = fn()
      if opened_identity and opened_identity ~= database_identity(self.config.data_file) then
        error(DATABASE_REPLACED_ERROR, 0)
      end

      return operation_result
    end)
    close_database(db)
    if not ok then error(result, 0) end
    return result
  end,

  is_retryable_database_error = function(_, err)
    if not err then return false end
    local err_str = tostring(err):lower()
    return err_str == DATABASE_REPLACED_ERROR:lower()
      or err_str:find("sqlite error:", 1, true) ~= nil
      or is_database_contention_error(err)
      or err_str:find("readonly", 1, true) ~= nil
      or err_str:find("read-only", 1, true) ~= nil
  end,

  execute_with_retry = function(self, fn)
    local last_error
    for _ = 1, MAX_IMMEDIATE_DATABASE_ATTEMPTS do
      local ok, result = pcall(self.execute_database_operation, self, fn)
      if ok then return true, result end
      if not self:is_retryable_database_error(result) then return false, result end
      last_error = result
      if is_database_contention_error(result) then break end
    end

    return false, last_error
  end,

  load_data = function(self)
    local ok, data = self:execute_with_retry(function()
      local count_result = self.Buffer:query():select("COUNT(*) AS count"):execute()
      local count = count_result and count_result[1] and count_result[1].count
      if type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
        error("Failed to count persisted time-tracker buffers.")
      end

      if count == 0 then return { roots = {} } end

      local buffers = self.Buffer:all()
      if buffers == nil then error("Failed to load persisted time-tracker buffers.") end

      local loaded_data = { roots = {} }

      for _, buffer in ipairs(buffers) do
        if not loaded_data.roots[buffer.cwd] then loaded_data.roots[buffer.cwd] = {} end
        if not loaded_data.roots[buffer.cwd][buffer.path] then loaded_data.roots[buffer.cwd][buffer.path] = {} end
        table.insert(loaded_data.roots[buffer.cwd][buffer.path], {
          start = buffer.start_time,
          ["end"] = buffer.end_time,
        })
      end

      return loaded_data
    end)
    if ok then return data end

    if not self:is_retryable_database_error(data) then error(data, 0) end

    vim.notify("TimeTracker: Failed to load persisted data. Error: " .. tostring(data), vim.log.levels.ERROR)
    return { roots = {} }
  end,

  start_session = function(self)
    local ok, id = self:execute_with_retry(function()
      return self.Session:create({
        start_time = vim.fn.localtime(),
        end_time = vim.fn.localtime(),
      })
    end)

    if not ok then
      vim.notify("TimeTracker: Failed to start session. Error: " .. tostring(id), vim.log.levels.ERROR)
      return false, self:is_retryable_database_error(id)
    end

    if not id then
      vim.notify("TimeTracker: Failed to create a new session (no ID returned).", vim.log.levels.ERROR)
      return false, false
    end

    self.current_session = {
      id = id,
      buffers = {},
    }
    return true
  end,

  handle_activity = function(self)
    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_trackable_buffer(bufnr) then return end

    -- session doesn't exist, create it
    if not self.current_session then
      local started = self:start_session()
      if not started then return end
    end

    -- store previous buffer activity on buffer change
    if self.current_buffer and self.current_buffer.bufnr ~= bufnr then
      local end_time = vim.fn.localtime()
      local ok, result = self:execute_with_retry(function()
        return self.Buffer:create({
          session_id = self.current_session.id,
          cwd = self.current_buffer.cwd,
          path = self.current_buffer.path,
          start_time = self.current_buffer.start,
          end_time = end_time,
        })
      end)

      if not ok then
        vim.notify("TimeTracker: Failed to record buffer activity. Error: " .. tostring(result), vim.log.levels.ERROR)
      end
    end

    -- set new current buffer on buffer change or when there is no current buffer
    if self.current_buffer == nil or self.current_buffer.bufnr ~= bufnr then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      local buf_cwd = vim.fn.getcwd()

      self.current_buffer = {
        bufnr = bufnr,
        cwd = buf_cwd,
        path = buf_path,
        name = vim.fn.fnamemodify(buf_path, ":t"),
        ft = vim.bo[bufnr].filetype,
        start = vim.fn.localtime(),
      }
    end

    -- create/reset timer
    if self.timer ~= nil then
      self.timer:stop()
      self.timer:close()
    end
    self.timer = vim.loop.new_timer()
    self.timer:start(self.config.tracking_timeout_seconds * 1000, 0, function()
      vim.schedule(function()
        if self.timer == nil then return end
        self:end_session()
        self.timer:stop()
        self.timer:close()
        self.timer = nil
      end)
    end)
    self.timer_deadline = vim.fn.localtime() + self.config.tracking_timeout_seconds + 60
  end,

  end_session = function(self)
    if not self.current_session then return end

    -- record current buffer
    if self.current_buffer then
      if vim.fn.localtime() <= self.timer_deadline then
        local end_time = vim.fn.localtime()
        local ok, result = self:execute_with_retry(function()
          return self.Buffer:create({
            session_id = self.current_session.id,
            cwd = self.current_buffer.cwd,
            path = self.current_buffer.path,
            start_time = self.current_buffer.start,
            end_time = end_time,
          })
        end)

        if not ok then
          vim.notify(
            "TimeTracker: Failed to record final buffer activity for session end. Error: " .. tostring(result),
            vim.log.levels.ERROR
          )
        end
      end

      self.current_buffer = nil
    end

    -- update session end time
    if self.current_session.id == nil then
      vim.notify("TimeTracker: Attempted to end a session with no session id.", vim.log.levels.ERROR)
    else
      local ok, result = self:execute_with_retry(function()
        return self.Session:update("id = " .. self.current_session.id, { end_time = vim.fn.localtime() })
      end)

      if not ok then
        vim.notify("TimeTracker: Failed to update session end time. Error: " .. tostring(result), vim.log.levels.ERROR)
      end
      self.current_session = nil
    end
  end,
}

return {
  TimeTracker = TimeTracker,
}
