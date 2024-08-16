---@meta

---@alias CWD string
---@alias BufferPath string

---@class Config
---@field data_file string
---@field tracking_events string[]
---@field tracking_timeout_seconds number
---@field storage string

---@class BufferSession
---@field start number
---@field end number

---@class Data
---@field roots table<CWD, table<BufferPath, BufferSession[]>>

---@class CurrentSession
---@field id number
---@field buffers table<CWD, table<BufferPath, BufferSession[]>>

---@class CurrentBuffer
---@field bufnr number
---@field cwd CWD
---@field path BufferPath
---@field start number

---@class TimeTracker
---@field impl SessionInterface|nil
---@field new fun(self: TimeTracker, session: SessionInterface): TimeTracker
---@field start_session fun(self: TimeTracker)
---@field handle_activity fun(self: TimeTracker)
---@field end_session fun(self: TimeTracker)
---@field load_data fun(self: TimeTracker): Data

---@class Interface
---@field interface any
---@field new fun(self: Interface, interface: any): Interface
---@field implements fun(self: Interface, interface: any): boolean

---@class SessionInterface
---@field new fun(self: SessionInterface, config: Config)
---@field init fun(self: SessionInterface)
---@field load_data fun(self: SessionInterface): Data
---@field start_session fun(self: SessionInterface)
---@field handle_activity fun(self: SessionInterface)
---@field end_session fun(self: SessionInterface)

---@class SqliteSession
---@field config Config
---@field Session ORMModel|nil
---@field Buffer ORMModel|nil
---@field current_session CurrentSession|nil
---@field current_buffer CurrentBuffer|nil
---@field timer uv_timer_t|nil
---@field timer_deadline number|nil
---@field new fun(self: SqliteSession, config: Config): SqliteSession
---@field init fun(self: SqliteSession)
---@field load_data fun(self: SqliteSession): Data
---@field start_session fun(self: SqliteSession)
---@field handle_activity fun(self: SqliteSession)
---@field end_session fun(self: SqliteSession)
