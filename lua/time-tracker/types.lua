---@meta

---@class Config
---@field data_file string
---@field tracking_events string[]
---@field tracking_timeout_seconds number
---@field buffer_tracking_enabled boolean

---@class Project
---@field name string
---@field path string

---@class WorkSessionBufferEntry
---@field buffer string
---@field duration number

---@class WorkSession
---@field path string
---@field start number
---@field end number
---@field duration number
---@field buffers? WorkSessionBufferEntry[]

--- @class TimeTracker
--- @field config Config
--- @field project Project
--- @field timer uv_timer_t
--- @field session_start number
--- @field buffers WorkSessionBufferEntry[]
--- @field active_buffer { number: number, path: string, start: number }
--- @field buffer_durations { [string]: number }
