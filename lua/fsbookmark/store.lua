local config = require("fsbookmark.config")
local root = require("fsbookmark.root")
local util = require("fsbookmark.util")

---@class Bookmark
---@field id string
---@field path string
---@field type "file"|"directory"
---@field description string
---@field labels string[]
---@field source string where the bookmark came from; always "manual" today
---@field metadata table free-form extension point for other plugins
---@field created_at integer
---@field updated_at integer
---@field scope "global"|"workspace" derived from the file it lives in; not stored

--- Persistence. This is the only module that knows a workspace exists — a
--- Bookmark does not carry its own location, and the public API never names one.
local M = {}

M.SCHEMA_VERSION = 1

---@class FSBookmarkCollection
---@field items Bookmark[]
---@field loaded boolean
---@field dirty boolean
---@field root string|nil
---@field name string|nil

---@type table<"global"|"workspace", FSBookmarkCollection>
M.collections = {
  global = { items = {}, loaded = false, dirty = false },
  workspace = { items = {}, loaded = false, dirty = false },
}

--- Merged view: global first, then the current workspace.
---@type Bookmark[]
M.items = {}

---@type table<string, Bookmark>
M.by_path = {}

--- Fields that are derived rather than persisted.
local DERIVED = { "scope" }

---@param bookmark Bookmark
---@return table
local function serialize(bookmark)
  local out = vim.deepcopy(bookmark)
  for _, field in ipairs(DERIVED) do
    out[field] = nil
  end
  return out
end

--- Coerce a decoded entry into a valid bookmark, or nil if unusable.
---@param raw table
---@param scope "global"|"workspace"
---@return Bookmark|nil
local function sanitize(raw, scope)
  if type(raw) ~= "table" or type(raw.path) ~= "string" or raw.path == "" then
    return nil
  end
  local now = os.time()
  return {
    id = type(raw.id) == "string" and raw.id or util.uuid(),
    path = util.normalize(raw.path),
    type = raw.type == "directory" and "directory" or "file",
    description = type(raw.description) == "string" and raw.description or "",
    labels = vim.islist(raw.labels) and raw.labels or {},
    source = type(raw.source) == "string" and raw.source ~= "" and raw.source or "manual",
    metadata = type(raw.metadata) == "table" and raw.metadata or {},
    created_at = tonumber(raw.created_at) or now,
    updated_at = tonumber(raw.updated_at) or now,
    scope = scope,
  }
end

--- Rebuild the merged view. Workspace entries win over global ones for the
--- same path: the more specific location is the one the user last wrote to.
local function merge()
  M.items = {}
  M.by_path = {}
  for _, scope in ipairs({ "global", "workspace" }) do
    for _, bookmark in ipairs(M.collections[scope].items) do
      if M.by_path[bookmark.path] then
        -- Replace the global entry in place so ordering stays stable.
        for i, existing in ipairs(M.items) do
          if existing.path == bookmark.path then
            M.items[i] = bookmark
            break
          end
        end
      else
        table.insert(M.items, bookmark)
      end
      M.by_path[bookmark.path] = bookmark
    end
  end
end

---@param scope "global"|"workspace"
---@return string|nil
function M.file(scope)
  local dir = config.dir()
  if scope == "global" then
    return vim.fs.joinpath(dir, "global.json")
  end
  local collection = M.collections.workspace
  if not collection.root then
    return nil
  end
  return vim.fs.joinpath(dir, "workspace", root.id(collection.root) .. ".json")
end

--- Move a pre-workspace `bookmarks.json` into the new layout, once.
local function migrate_legacy()
  local legacy = vim.fs.joinpath(vim.fs.dirname(config.dir()), "bookmarks.json")
  local target = M.file("global")
  if not vim.uv.fs_stat(legacy) or vim.uv.fs_stat(target) then
    return
  end
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  if vim.uv.fs_rename(legacy, target) then
    util.notify("migrated bookmarks.json to " .. target)
  end
end

--- Read one collection from disk.
---@param scope "global"|"workspace"
---@return boolean ok
local function read(scope)
  local collection = M.collections[scope]
  collection.items = {}
  collection.loaded = true
  collection.dirty = false

  local path = M.file(scope)
  local fd = path and io.open(path, "r")
  if not fd then
    return true
  end

  local content = fd:read("*a")
  fd:close()
  if vim.trim(content or "") == "" then
    return true
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    util.notify("failed to parse " .. path .. " — starting with an empty list", vim.log.levels.ERROR)
    return false
  end

  -- Accept both `{version, bookmarks}` and a bare array.
  local raw_items = vim.islist(decoded) and decoded or decoded.bookmarks
  local seen = {}
  for _, raw in ipairs(raw_items or {}) do
    local bookmark = sanitize(raw, scope)
    if bookmark and not seen[bookmark.path] then
      seen[bookmark.path] = true
      table.insert(collection.items, bookmark)
    end
  end

  return true
end

--- Point the workspace collection at the current root, loading it if it moved.
---@return boolean changed
local function sync_workspace()
  local collection = M.collections.workspace
  local current = config.options.workspace.enabled and root.current() or nil

  if collection.loaded and collection.root == current then
    return false
  end

  collection.root = current
  collection.name = current and root.name(current) or nil
  if not current then
    collection.items = {}
    collection.loaded = true
    collection.dirty = false
    return true
  end

  read("workspace")
  return true
end

--- Read everything from disk, replacing in-memory state.
---@return boolean ok
function M.load()
  migrate_legacy()
  local ok = read("global")
  M.collections.workspace.loaded = false
  sync_workspace()
  merge()
  return ok
end

--- Load once, then keep the workspace collection in step with the cwd/buffer.
function M.ensure()
  if not M.collections.global.loaded then
    M.load()
    return
  end
  if sync_workspace() then
    merge()
  end
end

--- Write one collection to disk atomically.
---@param scope "global"|"workspace"
---@return boolean ok
local function write(scope)
  local collection = M.collections[scope]
  local path = M.file(scope)
  if not path then
    return true
  end

  local payload = {
    version = M.SCHEMA_VERSION,
    bookmarks = vim.tbl_map(serialize, collection.items),
  }
  if scope == "workspace" then
    payload.root = collection.root
    payload.name = collection.name
  end

  local ok, encoded = pcall(vim.json.encode, payload)
  if not ok then
    util.notify("failed to encode bookmarks: " .. tostring(encoded), vim.log.levels.ERROR)
    return false
  end

  vim.fn.mkdir(vim.fs.dirname(path), "p")
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

  collection.dirty = false
  return true
end

--- Write every collection that has pending changes.
---@return boolean ok
function M.save()
  local ok = true
  for _, scope in ipairs({ "global", "workspace" }) do
    if M.collections[scope].dirty then
      ok = write(scope) and ok
    end
  end
  return ok
end

---@return boolean
function M.dirty()
  return M.collections.global.dirty or M.collections.workspace.dirty
end

--- Mark a collection as changed, persisting when autosave is on.
---@param scope "global"|"workspace"
function M.touch(scope)
  M.collections[scope].dirty = true
  if config.options.autosave then
    M.save()
  end
end

--- Where a path belongs: inside the workspace root it is workspace-scoped,
--- otherwise global. Nothing asks the user, and nothing stores the answer.
---@param path string
---@return "global"|"workspace"
function M.scope_for(path)
  local collection = M.collections.workspace
  if collection.root and root.contains(path, collection.root) then
    return "workspace"
  end
  return "global"
end

---@return string|nil root, string|nil name
function M.workspace()
  M.ensure()
  local collection = M.collections.workspace
  return collection.root, collection.name
end

---@param path string
---@return Bookmark|nil
function M.get(path)
  M.ensure()
  return M.by_path[util.normalize(path)]
end

---@param bookmark Bookmark
---@return "global"|"workspace" scope
function M.insert(bookmark)
  local scope = M.scope_for(bookmark.path)
  bookmark.scope = scope
  table.insert(M.collections[scope].items, bookmark)
  merge()
  return scope
end

---@param path string
---@return Bookmark|nil removed, "global"|"workspace"|nil scope
function M.delete(path)
  path = util.normalize(path)
  local bookmark = M.by_path[path]
  if not bookmark then
    return nil, nil
  end

  local scope = bookmark.scope
  local items = M.collections[scope].items
  for i, item in ipairs(items) do
    if item.path == path then
      table.remove(items, i)
      break
    end
  end

  merge()
  return bookmark, scope
end

--- Re-key a bookmark after its file moved, relocating it if the move crossed
--- the workspace boundary.
---@param from string
---@param to string
---@return Bookmark|nil bookmark, "global"|"workspace"|nil scope
function M.rekey(from, to)
  M.ensure()
  from, to = util.normalize(from), util.normalize(to)
  local bookmark = M.by_path[from]
  if not bookmark or from == to then
    return nil, nil
  end

  local was = bookmark.scope
  local now = M.scope_for(to)
  if was ~= now then
    for i, item in ipairs(M.collections[was].items) do
      if item.path == from then
        table.remove(M.collections[was].items, i)
        break
      end
    end
    table.insert(M.collections[now].items, bookmark)
    -- Both files changed; the caller only knows to flush one.
    M.collections[was].dirty = true
  end

  bookmark.path = to
  bookmark.scope = now
  bookmark.updated_at = os.time()
  merge()
  return bookmark, now
end

return M
