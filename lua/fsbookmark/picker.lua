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

--- Build picker items. `text` carries everything searchable so Snacks' own
--- matcher covers path, description and labels in one pass.
---@return table[]
local function finder()
  local fsbookmark = require("fsbookmark")
  local items = {}

  for index, bookmark in ipairs(fsbookmark.list()) do
    local broken = fsbookmark.is_broken(bookmark)
    local labels = table.concat(bookmark.labels or {}, " ")
    table.insert(items, {
      idx = index,
      text = table.concat({
        util.display_path(bookmark.path),
        bookmark.description or "",
        labels,
      }, " "),
      file = bookmark.path,
      dir = bookmark.type == "directory",
      bookmark = bookmark,
      broken = broken,
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
  }
  for name, action in pairs(map) do
    local key = keys[name]
    if key then
      input_keys[key] = { action, mode = { "n", "i" } }
    end
  end

  return {
    title = "Bookmarks",
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
