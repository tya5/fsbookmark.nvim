local config = require("fsbookmark.config")
local events = require("fsbookmark.events")
local search = require("fsbookmark.search")
local store = require("fsbookmark.store")
local util = require("fsbookmark.util")

local M = {}

M.events = events

---@class FSBookmarkFields
---@field description string|nil
---@field labels string[]|nil

--- Register a path. Returns the existing bookmark untouched if already present.
---@param path string|nil defaults to the current buffer
---@param fields FSBookmarkFields|nil
---@return Bookmark|nil bookmark, boolean created
function M.add(path, fields)
  store.ensure()
  path = M.resolve(path)
  if not path then
    return nil, false
  end

  local existing = store.by_path[path]
  if existing then
    return existing, false
  end

  local now = os.time()
  ---@type Bookmark
  local bookmark = {
    id = util.uuid(),
    path = path,
    type = util.type_of(path),
    description = (fields or {}).description or "",
    labels = (fields or {}).labels or {},
    created_at = now,
    updated_at = now,
  }

  store.insert(bookmark)
  store.touch()
  events.emit(events.ADD, bookmark)
  return bookmark, true
end

--- Unregister a path.
---@param path string|nil defaults to the current buffer
---@return Bookmark|nil removed
function M.remove(path)
  store.ensure()
  path = M.resolve(path)
  if not path then
    return nil
  end

  local removed = store.delete(path)
  if not removed then
    return nil
  end

  store.touch()
  events.emit(events.REMOVE, removed)
  return removed
end

--- Add the path if unregistered, remove it otherwise.
---@param path string|nil defaults to the current buffer
---@return boolean added true when the bookmark now exists
function M.toggle(path)
  store.ensure()
  path = M.resolve(path)
  if not path then
    return false
  end

  if store.by_path[path] then
    M.remove(path)
    return false
  end

  M.add(path)
  return true
end

---@param path string|nil defaults to the current buffer
---@return Bookmark|nil
function M.get(path)
  store.ensure()
  path = M.resolve(path)
  return path and store.by_path[path] or nil
end

--- All bookmarks, in insertion order.
---@return Bookmark[]
function M.list()
  store.ensure()
  return vim.deepcopy(store.items)
end

--- Fuzzy search over path, description and labels. Supports `label:foo` filters.
---@param query string|nil
---@return Bookmark[]
function M.search(query)
  store.ensure()
  return search.filter(store.items, query)
end

--- Patch a bookmark's mutable fields.
---@param path string
---@param data FSBookmarkFields
---@return Bookmark|nil
function M.update(path, data)
  store.ensure()
  path = M.resolve(path)
  local bookmark = path and store.by_path[path]
  if not bookmark then
    return nil
  end

  if data.description ~= nil then
    bookmark.description = data.description
  end
  if data.labels ~= nil then
    bookmark.labels = data.labels
  end
  bookmark.updated_at = os.time()

  store.touch()
  events.emit(events.UPDATE, bookmark)
  return bookmark
end

---@return boolean ok
function M.save()
  return store.save()
end

---@return boolean ok
function M.load()
  return store.load()
end

--- Resolve a user-supplied path, falling back to the current buffer.
---@param path string|nil
---@return string|nil
function M.resolve(path)
  if path == nil or path == "" then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then
      return nil
    end
    path = name
  end
  return util.normalize(path)
end

--- True when the bookmarked path no longer exists on disk.
---@param bookmark Bookmark
---@return boolean
function M.is_broken(bookmark)
  return not util.exists(bookmark.path)
end

--- Every label currently in use, sorted.
---@return string[]
function M.labels()
  store.ensure()
  local seen, out = {}, {}
  for _, bookmark in ipairs(store.items) do
    for _, label in ipairs(bookmark.labels or {}) do
      if not seen[label] then
        seen[label] = true
        table.insert(out, label)
      end
    end
  end
  table.sort(out)
  return out
end

--- Open the picker (Snacks).
---@param opts table|nil
function M.picker(opts)
  return require("fsbookmark.picker").open(opts)
end

--- Prompt for description then labels via `vim.ui.input`.
---@param path string|nil
---@param on_done fun(bookmark: Bookmark|nil)|nil
function M.edit(path, on_done)
  return require("fsbookmark.edit").edit(path, on_done)
end

--- Open a bookmark: files in the current window, directories via the explorer.
---@param bookmark Bookmark|string
function M.open(bookmark)
  if type(bookmark) == "string" then
    bookmark = M.get(bookmark) or { path = util.normalize(bookmark), type = util.type_of(bookmark) }
  end

  if bookmark.type == "directory" then
    local open = config.options.open_directory
    if open then
      open(bookmark.path)
    else
      require("fsbookmark.explorer").open_directory(bookmark.path)
    end
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(bookmark.path))
end

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  store.load()

  if config.options.watch then
    require("fsbookmark.watch").setup()
  end
  if config.options.explorer.enabled then
    require("fsbookmark.explorer").setup()
  end
  if config.options.keys.enabled then
    require("fsbookmark.keys").setup()
  end

  return M
end

return M
