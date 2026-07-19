local util = require("fsbookmark.util")

--- Resolves the workspace root for the current context.
---
--- This is the only module that knows how a workspace is identified. Nothing
--- here is part of the public API, and nothing else may depend on the order
--- below beyond "most specific wins".
local M = {}

M.markers = { ".git" }

---@type table<string, string|false>
local cache = {}

--- LSP workspace root for a buffer, if any client reports one.
---@param buf integer
---@return string|nil
local function lsp_root(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    -- `root_dir` is nil for single-file clients, which is exactly the case
    -- where we want to fall through to git.
    if client.config and client.config.root_dir then
      return client.config.root_dir
    end
    if client.root_dir then
      return client.root_dir
    end
  end
  return nil
end

--- Nearest ancestor containing a marker.
---@param start string
---@return string|nil
local function marker_root(start)
  local found = vim.fs.find(M.markers, { path = start, upward = true, limit = 1 })[1]
  return found and vim.fs.dirname(found) or nil
end

--- Directory to start searching from: the current buffer's, else cwd.
---@param buf integer
---@return string
local function origin(buf)
  local name = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ""
  if name ~= "" and not name:match("^%a+://") then
    return vim.fs.dirname(util.normalize(name))
  end
  return util.normalize(vim.uv.cwd() or ".")
end

--- The workspace root for the current context, or nil when there is none.
---
--- Order: LSP workspace root, then the nearest marker (`.git`), then the cwd.
--- The cwd always resolves, so this returns nil only when told to.
---@param buf integer|nil
---@return string|nil
function M.current(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local from = origin(buf)
  local cached = cache[from]
  if cached ~= nil then
    return cached or nil
  end

  local root = lsp_root(buf) or marker_root(from) or vim.uv.cwd()
  root = root and util.normalize(root) or nil
  cache[from] = root or false
  return root
end

--- Human-readable workspace name.
---@param root string
---@return string
function M.name(root)
  return vim.fn.fnamemodify(root, ":t")
end

--- Stable per-root file name. The scheme is an implementation detail; the name
--- prefix exists only so the directory is readable when debugging.
---@param root string
---@return string
function M.id(root)
  local slug = M.name(root):gsub("[^%w%-_%.]", "_")
  return ("%s-%s"):format(slug, vim.fn.sha256(root):sub(1, 12))
end

--- True when `path` lives inside `root`.
---@param path string
---@param root string
---@return boolean
function M.contains(path, root)
  return path == root or vim.startswith(path, root .. "/")
end

function M.clear_cache()
  cache = {}
end

return M
