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
---@field scope "global"|"workspace"|"shared" derived from the file it lives in; not stored

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

--- Ordered least- to most-specific: later scopes win on a duplicate path.
M.SCOPES = { "global", "workspace", "shared" }

---@type table<"global"|"workspace"|"shared", FSBookmarkCollection>
M.collections = {
  global = { items = {}, loaded = false, dirty = false },
  workspace = { items = {}, loaded = false, dirty = false },
  shared = { items = {}, loaded = false, dirty = false },
}

--- Merged view: global first, then the current workspace.
---@type Bookmark[]
M.items = {}

---@type table<string, Bookmark>
M.by_path = {}

--- Fields that are derived rather than persisted.
local DERIVED = { "scope" }

--- Reading order for the shared file: what a human wants to see first.
local FIELD_ORDER = {
  "version",
  "bookmarks",
  "path",
  "type",
  "description",
  "labels",
}

---@param bookmark Bookmark
---@param base string|nil root to make the path relative to
---@return table
local function serialize(bookmark, base)
  local out = vim.deepcopy(bookmark)
  for _, field in ipairs(DERIVED) do
    out[field] = nil
  end

  if not base then
    return out
  end

  -- A checked-in file is read on other machines, where an absolute path is
  -- meaningless. Store it relative to the repository root.
  if root.contains(bookmark.path, base) then
    out.path = bookmark.path == base and "." or bookmark.path:sub(#base + 2)
  end

  -- Ids and timestamps are per-machine bookkeeping: keeping them would make
  -- every save a diff, and they are regenerated on read anyway.
  out.id, out.created_at, out.updated_at = nil, nil, nil
  if out.source == "manual" then
    out.source = nil
  end
  if vim.tbl_isempty(out.metadata or {}) then
    out.metadata = nil
  end
  if vim.tbl_isempty(out.labels or {}) then
    out.labels = nil
  end

  return out
end

--- Coerce a decoded entry into a valid bookmark, or nil if unusable.
---@param raw table
---@param scope "global"|"workspace"
---@return Bookmark|nil
local function sanitize(raw, scope, base)
  if type(raw) ~= "table" or type(raw.path) ~= "string" or raw.path == "" then
    return nil
  end

  local path = raw.path
  -- Relative paths only occur in the shared file; resolve them against the
  -- repository root they were written relative to.
  if base and not vim.startswith(path, "/") and not path:match("^~") then
    path = vim.fs.joinpath(base, path)
  end

  local now = os.time()
  return {
    id = type(raw.id) == "string" and raw.id or util.uuid(),
    path = util.normalize(path),
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
  for _, scope in ipairs(M.SCOPES) do
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
  if scope == "global" then
    return vim.fs.joinpath(config.dir(), "global.json")
  end

  local workspace_root = M.collections.workspace.root
  if not workspace_root then
    return nil
  end

  if scope == "shared" then
    if not config.options.shared.enabled then
      return nil
    end
    -- Lives in the repository, not in stdpath("data").
    return vim.fs.joinpath(workspace_root, config.options.shared.file)
  end

  return vim.fs.joinpath(config.dir(), "workspace", root.id(workspace_root) .. ".json")
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
  local base = scope == "shared" and collection.root or nil
  local seen = {}
  for _, raw in ipairs(raw_items or {}) do
    local bookmark = sanitize(raw, scope, base)
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

  local shared = M.collections.shared
  shared.root = current
  shared.name = collection.name

  if not current then
    for _, scope in ipairs({ "workspace", "shared" }) do
      M.collections[scope].items = {}
      M.collections[scope].loaded = true
      M.collections[scope].dirty = false
    end
    return true
  end

  read("workspace")
  read("shared")
  return true
end

--- Read everything from disk, replacing in-memory state.
---@return boolean ok
function M.load()
  migrate_legacy()
  local ok = read("global")
  M.collections.workspace.loaded = false
  M.collections.shared.loaded = false
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

  -- The shared file is committed, so it carries neither absolute paths nor the
  -- machine-specific root that the personal workspace file records.
  local base = scope == "shared" and collection.root or nil
  local payload = {
    version = M.SCHEMA_VERSION,
    bookmarks = vim.tbl_map(function(bookmark)
      return serialize(bookmark, base)
    end, collection.items),
  }
  if scope == "workspace" then
    payload.root = collection.root
    payload.name = collection.name
  end

  -- The shared file is reviewed in pull requests, so it is written indented
  -- and with a stable key order; the private files stay compact.
  local ok, encoded
  if scope == "shared" then
    ok, encoded = pcall(util.encode_pretty, payload, FIELD_ORDER)
    if ok then
      encoded = encoded .. "\n"
    end
  else
    ok, encoded = pcall(vim.json.encode, payload)
  end
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
  for _, scope in ipairs(M.SCOPES) do
    if M.collections[scope].dirty then
      ok = write(scope) and ok
    end
  end
  return ok
end

---@return boolean
function M.dirty()
  for _, scope in ipairs(M.SCOPES) do
    if M.collections[scope].dirty then
      return true
    end
  end
  return false
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

--- Move a bookmark to another collection, keeping its identity.
---@param path string
---@param scope "global"|"workspace"|"shared"
---@return Bookmark|nil bookmark, string|nil error
function M.move(path, scope)
  M.ensure()
  path = util.normalize(path)
  local bookmark = M.by_path[path]
  if not bookmark then
    return nil, "not bookmarked: " .. util.display_path(path)
  end

  local from = bookmark.scope
  if from == scope then
    return bookmark, nil
  end
  if not M.file(scope) then
    return nil, ("no %s file available here"):format(scope)
  end
  -- A checked-in file can only describe paths inside the repository.
  if scope == "shared" and not root.contains(path, M.collections.shared.root or "") then
    return nil, "outside the workspace: " .. util.display_path(path)
  end

  for i, item in ipairs(M.collections[from].items) do
    if item.path == path then
      table.remove(M.collections[from].items, i)
      break
    end
  end
  bookmark.scope = scope
  bookmark.updated_at = os.time()
  table.insert(M.collections[scope].items, bookmark)

  M.collections[from].dirty = true
  M.collections[scope].dirty = true
  merge()
  return bookmark, nil
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
