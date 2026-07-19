local config = require("fsbookmark.config")
local util = require("fsbookmark.util")

---@class Bookmark
---@field id string
---@field path string
---@field type "file"|"directory"
---@field description string
---@field labels string[]
---@field created_at integer
---@field updated_at integer

local M = {}

M.SCHEMA_VERSION = 1

---@type Bookmark[]
M.items = {}

---@type table<string, Bookmark>
M.by_path = {}

M.loaded = false
M.dirty = false

local function reindex()
  M.by_path = {}
  for _, bookmark in ipairs(M.items) do
    M.by_path[bookmark.path] = bookmark
  end
end

--- Coerce a decoded entry into a valid bookmark, or nil if unusable.
---@param raw table
---@return Bookmark|nil
local function sanitize(raw)
  if type(raw) ~= "table" or type(raw.path) ~= "string" or raw.path == "" then
    return nil
  end
  local path = util.normalize(raw.path)
  local now = os.time()
  return {
    id = type(raw.id) == "string" and raw.id or util.uuid(),
    path = path,
    type = raw.type == "directory" and "directory" or "file",
    description = type(raw.description) == "string" and raw.description or "",
    labels = vim.islist(raw.labels) and raw.labels or {},
    created_at = tonumber(raw.created_at) or now,
    updated_at = tonumber(raw.updated_at) or now,
  }
end

--- Read bookmarks from disk, replacing in-memory state.
---@return boolean ok
function M.load()
  M.items = {}
  -- Must be cleared alongside `items`: it doubles as the duplicate check below,
  -- so stale keys would make every reloaded bookmark look like a duplicate.
  M.by_path = {}
  M.loaded = true
  M.dirty = false

  local path = config.file()
  local fd = io.open(path, "r")
  if not fd then
    reindex()
    return true
  end

  local content = fd:read("*a")
  fd:close()

  if vim.trim(content or "") == "" then
    reindex()
    return true
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    util.notify("failed to parse " .. path .. " — starting with an empty list", vim.log.levels.ERROR)
    reindex()
    return false
  end

  -- Accept both `{version, bookmarks}` and a bare array.
  local raw_items = vim.islist(decoded) and decoded or decoded.bookmarks
  for _, raw in ipairs(raw_items or {}) do
    local bookmark = sanitize(raw)
    -- First entry wins; a duplicated path would otherwise desync the index.
    if bookmark and not M.by_path[bookmark.path] then
      table.insert(M.items, bookmark)
      M.by_path[bookmark.path] = bookmark
    end
  end

  reindex()
  return true
end

--- Load once, lazily. Every public API entry point goes through this.
function M.ensure()
  if not M.loaded then
    M.load()
  end
end

--- Write bookmarks to disk atomically.
---@return boolean ok
function M.save()
  local path = config.file()
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local ok, encoded = pcall(vim.json.encode, {
    version = M.SCHEMA_VERSION,
    bookmarks = M.items,
  })
  if not ok then
    util.notify("failed to encode bookmarks: " .. tostring(encoded), vim.log.levels.ERROR)
    return false
  end

  local tmp = path .. ".tmp"
  local fd, err = io.open(tmp, "w")
  if not fd then
    util.notify("failed to write " .. tmp .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  fd:write(encoded)
  fd:close()

  local renamed, rename_err = vim.uv.fs_rename(tmp, path)
  if not renamed then
    util.notify("failed to save bookmarks: " .. tostring(rename_err), vim.log.levels.ERROR)
    return false
  end

  M.dirty = false
  return true
end

--- Mark state as changed, persisting when autosave is on.
function M.touch()
  M.dirty = true
  if config.options.autosave then
    M.save()
  end
end

---@param path string
---@return Bookmark|nil
function M.get(path)
  M.ensure()
  return M.by_path[util.normalize(path)]
end

---@param bookmark Bookmark
function M.insert(bookmark)
  table.insert(M.items, bookmark)
  M.by_path[bookmark.path] = bookmark
end

---@param path string
---@return Bookmark|nil removed
function M.delete(path)
  path = util.normalize(path)
  local bookmark = M.by_path[path]
  if not bookmark then
    return nil
  end
  M.by_path[path] = nil
  for i, item in ipairs(M.items) do
    if item.path == path then
      table.remove(M.items, i)
      break
    end
  end
  return bookmark
end

--- Re-key a bookmark after its file moved.
---@param from string
---@param to string
---@return Bookmark|nil
function M.rekey(from, to)
  from, to = util.normalize(from), util.normalize(to)
  local bookmark = M.by_path[from]
  if not bookmark or from == to then
    return nil
  end
  M.by_path[from] = nil
  bookmark.path = to
  bookmark.updated_at = os.time()
  M.by_path[to] = bookmark
  return bookmark
end

return M
