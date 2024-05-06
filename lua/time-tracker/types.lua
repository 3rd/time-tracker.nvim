---@meta

---@alias CWD string
---@alias BufferPath string

---@class Config
---@field data_file string
---@field tracking_events string[]
---@field tracking_timeout_seconds number

---@class BufferSession
---@field start number
---@field end number

---@class Data
---@field roots table<CWD, table<BufferPath, BufferSession[]>>

---@class CurrentSession
---@field buffers table<CWD, table<BufferPath, BufferSession[]>>

---@class CurrentBuffer
---@field bufnr number
---@field cwd CWD
---@field path BufferPath
---@field start number

---@class TimeTracker
---@field config Config
---@field timer uv_timer_t|nil
---@field current_session CurrentSession|nil
---@field current_buffer CurrentBuffer|nil
---@field new fun(self: TimeTracker, config: Config): TimeTracker
---@field start_session fun(self: TimeTracker, bufnr: number)
---@field handle_activity fun(self: TimeTracker)
---@field end_session fun(self: TimeTracker)
---@field load_data fun(self: TimeTracker): Data
---@field save_data fun(self: TimeTracker, data: Data)
