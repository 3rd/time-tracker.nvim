local utils = require("time-tracker/utils")

--- @type TimeTracker
local TimeTracker = {
  --- @type Config
  config = nil,
  current_buffer = nil,
  current_session = nil,

  new = function(self, config)
    local tracker = {
      config = config,
    }
    setmetatable(tracker, self)
    ---@diagnostic disable-next-line: inject-field
    self.__index = self
    return tracker
  end,

  load_data = function(self)
    local ok, data = pcall(vim.fn.readfile, self.config.data_file)
    if not ok then return { roots = {} } end
    return vim.fn.json_decode(data)
  end,

  save_data = function(self, data)
    local json = vim.fn.json_encode(data)
    local ok, err = pcall(vim.fn.writefile, { json }, self.config.data_file)
    if not ok then vim.notify("Failed to save time tracker data: " .. err, vim.log.levels.ERROR) end
  end,

  start_session = function(self, bufnr)
    if not utils.is_trackable_buffer(bufnr) then return end

    self.current_session = {
      buffers = {},
    }
  end,

  handle_activity = function(self)
    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_trackable_buffer(bufnr) then return end

    -- session doesn't exist, create it
    if not self.current_session then self:start_session(bufnr) end

    -- store previous buffer activity on buffer change
    if self.current_buffer and self.current_buffer.bufnr ~= bufnr then
      local buf_cwd = self.current_buffer.cwd
      local buf_path = self.current_buffer.path

      ---@type BufferSession
      local entry = {
        start = self.current_buffer.start,
        ["end"] = vim.fn.localtime(),
      }

      if not self.current_session.buffers[buf_cwd] then self.current_session.buffers[buf_cwd] = {} end
      if not self.current_session.buffers[buf_cwd][buf_path] then
        self.current_session.buffers[buf_cwd][buf_path] = {}
      end
      table.insert(self.current_session.buffers[buf_cwd][buf_path], entry)
    end

    -- set new current buffer on buffer change or when there is no current buffer
    if self.current_buffer == nil or self.current_buffer.bufnr ~= bufnr then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      local buf_cwd = vim.fn.getcwd()

      self.current_buffer = {
        bufnr = bufnr,
        cwd = buf_cwd,
        path = buf_path,
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
        self:end_session()
        self.timer:stop()
        self.timer:close()
        self.timer = nil
      end)
    end)
  end,

  end_session = function(self)
    if not self.current_session then return end

    -- record current buffer
    if self.current_buffer then
      local buf_cwd = self.current_buffer.cwd
      local buf_path = self.current_buffer.path

      ---@type BufferSession
      local entry = {
        start = self.current_buffer.start,
        ["end"] = vim.fn.localtime(),
      }

      if not self.current_session.buffers[buf_cwd] then self.current_session.buffers[buf_cwd] = {} end
      if not self.current_session.buffers[buf_cwd][buf_path] then
        self.current_session.buffers[buf_cwd][buf_path] = {}
      end
      table.insert(self.current_session.buffers[buf_cwd][buf_path], entry)

      self.current_buffer = nil
    end

    -- save session
    local data = self:load_data()
    for cwd, buffers in pairs(self.current_session.buffers) do
      if not data.roots[cwd] then data.roots[cwd] = {} end
      for path, sessions in pairs(buffers) do
        if not data.roots[cwd][path] then data.roots[cwd][path] = {} end
        for _, session in ipairs(sessions) do
          table.insert(data.roots[cwd][path], session)
        end
      end
    end
    self:save_data(data)
    self.current_session = nil
  end,
}

return {
  TimeTracker = TimeTracker,
}
