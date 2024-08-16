--- @param bufnr number
--- @return boolean
local is_trackable_buffer = function(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  if vim.fn.buflisted(bufnr) == 0 then return false end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if vim.fn.filereadable(bufname) ~= 1 then return false end
  return true
end

--- @param duration number
--- @return string
local format_duration = function(duration)
  local hours = math.floor(duration / 3600)
  local minutes = math.floor((duration % 3600) / 60)
  local seconds = duration % 60
  return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

--- @param path string
--- @return string
local format_path_friendly = function(path)
  if path == nil or path == "" then return "[unknown]" end
  return vim.fn.fnamemodify(vim.fn.expand(path), ":~:.")
end

--- @param value any
--- @param array any[]
local in_array = function(value, array)
  for _, v in ipairs(array) do
    if v == value then return true end
  end
  return false
end

return {
  is_trackable_buffer = is_trackable_buffer,
  format_duration = format_duration,
  format_path_friendly = format_path_friendly,
  in_array = in_array,
}
