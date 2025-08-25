local orm = require("sqlite.orm")
local sqlite = require("sqlite")
local utils = require("time-tracker/utils")

---@type TimeTracker
local TimeTracker = {
  --- @type Config
  config = nil,
  current_buffer = nil,
  current_session = nil,
  Session = nil,
  Buffer = nil,
  db = nil,
  reconnect_attempts = 0,
  max_reconnect_attempts = 3,

  new = function(self, config)
    local tracker = {
      config = config,
    }
    setmetatable(tracker, self)
    self.__index = self

    local ok, err = pcall(function()
      tracker:init_db()
    end)
    if not ok then
      vim.notify("TimeTracker: Failed to initialize the database. Error: " .. tostring(err), vim.log.levels.ERROR)
      return nil
    end

    return tracker
  end,

  init_db = function(self)
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

    -- local db = sqlite.open(self.config.data_file, { debug = true })
    self.db = sqlite.open(self.config.data_file)
    self.Session:connect(self.db)
    self.Buffer:connect(self.db)
  end,

  is_readonly_error = function(self, err)
    if not err then return false end
    local err_str = tostring(err):lower()
    return err_str:find("readonly") ~= nil or err_str:find("read%-only") ~= nil or err_str:find("locked") ~= nil
  end,

  reconnect_db = function(self)
    vim.notify("TimeTracker: Attempting to reconnect to database...", vim.log.levels.INFO)

    -- close existing connection if it exists
    if self.db then
      pcall(function()
        self.db:close()
      end)
      self.db = nil
    end

    -- wait a bit before reconnecting
    vim.wait(100 * (2 ^ self.reconnect_attempts))

    -- reinitialize the database
    local ok, err = pcall(function()
      self:init_db()
    end)

    if ok then
      self.reconnect_attempts = 0
      vim.notify("TimeTracker: Successfully reconnected to database", vim.log.levels.INFO)
      return true
    else
      self.reconnect_attempts = self.reconnect_attempts + 1
      vim.notify("TimeTracker: Failed to reconnect. Error: " .. tostring(err), vim.log.levels.WARN)
      return false
    end
  end,

  execute_with_retry = function(self, fn, description)
    local max_attempts = 3
    local attempt = 0

    while attempt < max_attempts do
      attempt = attempt + 1
      local ok, result = pcall(fn)

      if ok then
        return true, result
      elseif self:is_readonly_error(result) then
        vim.notify(
          string.format(
            "TimeTracker: Read-only error detected during %s (attempt %d/%d)",
            description,
            attempt,
            max_attempts
          ),
          vim.log.levels.WARN
        )

        if attempt < max_attempts and self.reconnect_attempts < self.max_reconnect_attempts then
          if self:reconnect_db() then
            -- retry the operation
            vim.notify(string.format("TimeTracker: Retrying %s after reconnection", description), vim.log.levels.INFO)
          else
            -- reconnection failed
            return false, result
          end
        else
          vim.notify(
            string.format("TimeTracker: Max reconnection attempts reached for %s", description),
            vim.log.levels.ERROR
          )
          return false, result
        end
      else
        -- non-readonly error, don't retry
        return false, result
      end
    end

    return false, "Max attempts exceeded"
  end,

  load_data = function(self)
    local buffers = self.Buffer:all()
    local data = { roots = {} }

    for _, buffer in ipairs(buffers) do
      if not data.roots[buffer.cwd] then data.roots[buffer.cwd] = {} end
      if not data.roots[buffer.cwd][buffer.path] then data.roots[buffer.cwd][buffer.path] = {} end
      table.insert(data.roots[buffer.cwd][buffer.path], {
        start = buffer.start_time,
        ["end"] = buffer.end_time,
      })
    end

    return data
  end,

  start_session = function(self)
    local ok, id = self:execute_with_retry(function()
      return self.Session:create({
        start_time = vim.fn.localtime(),
        end_time = vim.fn.localtime(),
      })
    end, "session creation")

    if not ok then
      vim.notify("TimeTracker: Failed to start session. Error: " .. tostring(id), vim.log.levels.ERROR)
      return
    end

    if not id then
      vim.notify("TimeTracker: Failed to create a new session (no ID returned).", vim.log.levels.ERROR)
      return
    end

    self.current_session = {
      id = id,
      buffers = {},
    }
  end,

  handle_activity = function(self)
    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_trackable_buffer(bufnr) then return end

    -- session doesn't exist, create it
    if not self.current_session then
      self:start_session()
      if not self.current_session then
        vim.api.nvim_notify("Failed to create session record", vim.log.levels.ERROR, {})
        return
      end
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
      end, "buffer activity recording")

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
        end, "final buffer activity recording")

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
      end, "session end time update")

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
