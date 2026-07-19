local config = require("fsbookmark.config")
local util = require("fsbookmark.util")

--- Shared presentation for every picker backend. Snacks renders its own
--- highlighted columns; the plain-text backends use `line` from here so all
--- three agree on what a bookmark looks like.
local M = {}

--- One display line: markers, name, description, labels, path.
---@param bookmark Bookmark
---@param opts { show_scope?: boolean, broken?: boolean }|nil
---@return string
function M.line(bookmark, opts)
  opts = opts or {}
  local icons = config.options.icons
  local parts = {}

  if opts.show_scope then
    table.insert(parts, icons[bookmark.scope] or icons.global)
  end
  table.insert(parts, opts.broken and icons.broken or icons.bookmark)

  table.insert(parts, vim.fn.fnamemodify(bookmark.path, ":t"))
  if (bookmark.description or "") ~= "" then
    table.insert(parts, bookmark.description)
  end
  if #(bookmark.labels or {}) > 0 then
    table.insert(parts, table.concat(bookmark.labels, " "))
  end
  table.insert(parts, util.display_path(bookmark.path))

  return table.concat(parts, "  ")
end

--- Bookmarks for a query, each paired with its display line.
---@param query string|nil
---@return { bookmark: Bookmark, line: string, broken: boolean }[]
function M.list(query)
  local fsbookmark = require("fsbookmark")
  local show_scope = fsbookmark.workspace() ~= nil
  local out = {}

  for _, bookmark in ipairs(fsbookmark.search(query)) do
    local broken = fsbookmark.is_broken(bookmark)
    table.insert(out, {
      bookmark = bookmark,
      broken = broken,
      line = M.line(bookmark, { show_scope = show_scope, broken = broken }),
    })
  end

  return out
end

return M
