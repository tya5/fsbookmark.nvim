local M = {}

--- Normalize a path into the canonical form used as the bookmark key.
--- Absolute, `~` expanded, symlinks resolved, no trailing slash.
---
--- Symlinks are resolved because Neovim itself hands out resolved buffer names
--- (on macOS `/var/...` becomes `/private/var/...`); without this the same file
--- reached two ways would produce two bookmarks.
---@param path string
---@return string
function M.normalize(path)
  path = vim.fs.normalize(vim.fn.resolve(vim.fn.fnamemodify(path, ":p")))
  if #path > 1 then
    path = path:gsub("/+$", "")
  end
  return path
end

---@param path string
---@return "file"|"directory"
function M.type_of(path)
  return vim.fn.isdirectory(path) == 1 and "directory" or "file"
end

---@param path string
---@return boolean
function M.exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

--- Path relative to cwd when inside it, otherwise `~`-shortened.
---@param path string
---@return string
function M.display_path(path)
  local cwd = M.normalize(vim.uv.cwd() or ".")
  if path == cwd then
    return "."
  end
  if vim.startswith(path, cwd .. "/") then
    return path:sub(#cwd + 2)
  end
  return vim.fn.fnamemodify(path, ":~")
end

local counter = 0

---@return string
function M.uuid()
  counter = counter + 1
  return string.format("%x-%x-%x", os.time(), counter, math.random(0, 0xffffff))
end

---@param msg string
---@param level integer|nil
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "fsbookmark" })
end

--- Split a CSV string into a trimmed, de-duplicated list.
---@param str string
---@return string[]
function M.parse_csv(str)
  local out, seen = {}, {}
  for item in (str or ""):gmatch("[^,]+") do
    local trimmed = vim.trim(item)
    if trimmed ~= "" and not seen[trimmed] then
      seen[trimmed] = true
      table.insert(out, trimmed)
    end
  end
  return out
end

return M
