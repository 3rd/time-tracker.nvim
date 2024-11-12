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

  new = function(self, config)
    local tracker = {
      config = config,
    }
    setmetatable(tracker, self)
    self.__index = self
    tracker:init_db()
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
    local db = sqlite.open(self.config.data_file)
    self.Session:connect(db)
    self.Buffer:connect(db)
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
    local id = self.Session:create({
      start_time = vim.fn.localtime(),
      end_time = vim.fn.localtime(),
    })
    self.current_session = {
      id = id,
      buffers = {},
    }
  end,

  handle_activity = function(self)
    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_trackable_buffer(bufnr) then return end

    -- session doesn't exist, create it
    if not self.current_session then self:start_session() end

    -- store previous buffer activity on buffer change
    if self.current_buffer and self.current_buffer.bufnr ~= bufnr then
      local end_time = vim.fn.localtime()
      self.Buffer:create({
        session_id = self.current_session.id,
        cwd = self.current_buffer.cwd,
        path = self.current_buffer.path,
        start_time = self.current_buffer.start,
        end_time = end_time,
      })
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
        self.Buffer:create({
          session_id = self.current_session.id,
          cwd = self.current_buffer.cwd,
          path = self.current_buffer.path,
          start_time = self.current_buffer.start,
          end_time = end_time,
        })
      end

      self.current_buffer = nil
    end

    -- update session end time
    self.Session:update("id = " .. self.current_session.id, { end_time = vim.fn.localtime() })

    self.current_session = nil
  end,
}

return {
  TimeTracker = TimeTracker,
}
