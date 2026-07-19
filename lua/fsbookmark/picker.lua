local config = require("fsbookmark.config")
local util = require("fsbookmark.util")

local M = {}

---@return table|nil
local function snacks()
  local ok, mod = pcall(require, "snacks")
  if not ok or not mod.picker then
    util.notify("snacks.nvim with the picker enabled is required for the picker", vim.log.levels.ERROR)
    return nil
  end
  return mod
end

--- Build picker items for the current prompt.
---
--- The source runs `live`, so the whole prompt arrives here as
--- `ctx.filter.search` and Snacks' own matcher sits idle with an empty pattern.
--- That is what lets `label:core` mean what `search.lua` says it means instead
--- of being fuzzy-matched as literal text — and it means the ranking below is
--- the display order, since an empty matcher pattern preserves finder order.
---@param _opts table|nil
---@param ctx table|nil
---@return table[]
local function finder(_opts, ctx)
  local fsbookmark = require("fsbookmark")
  local query = ctx and ctx.filter and ctx.filter.search or ""
  local workspace = fsbookmark.workspace()
  local items = {}

  for index, bookmark in ipairs(fsbookmark.search(query)) do
    table.insert(items, {
      idx = index,
      -- Required to be a non-nil string; filtering already happened above, so
      -- this only feeds the formatter and tie-break sorting.
      text = util.display_path(bookmark.path),
      file = bookmark.path,
      dir = bookmark.type == "directory",
      bookmark = bookmark,
      broken = fsbookmark.is_broken(bookmark),
      show_scope = workspace ~= nil,
    })
  end

  return items
end

---@param item table
---@return table[]
local function format(item)
  local Snacks = require("snacks")
  local align = Snacks.picker.util.align
  local icons = config.options.icons
  local bookmark = item.bookmark
  local out = {}

  -- The scope column only appears when there is a workspace to contrast with;
  -- without one every row would carry the same marker.
  if item.show_scope then
    local scoped = bookmark.scope == "workspace"
    table.insert(out, { (scoped and icons.workspace or icons.global) .. " ", "SnacksPickerSpecial" })
  end

  local icon = item.broken and icons.broken or icons.bookmark
  table.insert(out, { icon .. " ", item.broken and "SnacksPickerLinkBroken" or "SnacksPickerLabel" })

  local name = vim.fn.fnamemodify(bookmark.path, ":t")
  local name_hl = item.broken and "SnacksPickerPathHidden"
    or (bookmark.type == "directory" and "SnacksPickerDirectory" or "SnacksPickerFile")
  table.insert(out, { align(name, 28, { truncate = true }), name_hl })
  table.insert(out, { " " })

  table.insert(out, { align(bookmark.description or "", 34, { truncate = true }), "SnacksPickerDesc" })
  table.insert(out, { " " })

  for _, label in ipairs(bookmark.labels or {}) do
    table.insert(out, { label, "SnacksPickerLabel" })
    table.insert(out, { " " })
  end

  table.insert(out, { util.display_path(bookmark.path), "SnacksPickerPathHidden" })
  return out
end

--- The Snacks source definition. Register it under
--- `opts.picker.sources.fsbookmark` to get `Snacks.picker.fsbookmark()`.
---@return table
function M.source()
  local fsbookmark = require("fsbookmark")
  local keys = config.options.picker.keys

  local actions = {
    fsbookmark_edit = function(picker, item)
      if not item then
        return
      end
      require("fsbookmark.edit").edit(item.bookmark.path, function()
        picker:find()
      end)
    end,
    fsbookmark_delete = function(picker, item)
      local selected = picker:selected({ fallback = true })
      for _, entry in ipairs(selected) do
        fsbookmark.remove(entry.bookmark.path)
      end
      picker.list:set_selected()
      picker:find()
    end,
    fsbookmark_reload = function(picker)
      fsbookmark.load()
      picker:find()
    end,
    fsbookmark_reveal = function(picker, item)
      if not item then
        return
      end
      picker:close()
      local bookmark = item.bookmark
      -- Reveal the file's parent; a bookmarked directory reveals itself.
      local dir = bookmark.type == "directory" and bookmark.path or vim.fs.dirname(bookmark.path)
      require("fsbookmark.explorer").open_directory(dir)
    end,
    fsbookmark_yank = function(_, item)
      if not item then
        return
      end
      vim.fn.setreg(vim.v.register or '"', item.bookmark.path)
      vim.fn.setreg("+", item.bookmark.path)
      util.notify("copied " .. item.bookmark.path)
    end,
  }

  local input_keys = {}
  local map = {
    edit = "fsbookmark_edit",
    delete = "fsbookmark_delete",
    reload = "fsbookmark_reload",
    yank = "fsbookmark_yank",
    reveal = "fsbookmark_reveal",
  }
  for name, action in pairs(map) do
    local key = keys[name]
    if key then
      input_keys[key] = { action, mode = { "n", "i" } }
    end
  end

  local _, workspace_name = fsbookmark.workspace()

  return {
    title = workspace_name and ("Bookmarks (%s)"):format(workspace_name) or "Bookmarks",
    -- `live` hands the raw prompt to the finder and keeps the built-in matcher
    -- out of the way; see the comment on `finder`.
    live = true,
    supports_live = true,
    -- Live sources must stay open on zero results, or a half-typed
    -- `label:c` would close the picker.
    show_empty = true,
    finder = finder,
    format = format,
    actions = actions,
    win = {
      input = { keys = input_keys },
      list = { keys = input_keys },
    },
    confirm = function(picker, item)
      picker:close()
      if item then
        fsbookmark.open(item.bookmark)
      end
    end,
  }
end

--- Open the bookmark picker.
---@param opts table|nil forwarded to `Snacks.picker.pick`
function M.open(opts)
  local Snacks = snacks()
  if not Snacks then
    return
  end
  return Snacks.picker.pick(vim.tbl_deep_extend("force", { source = "fsbookmark" }, M.source(), opts or {}))
end

return M
