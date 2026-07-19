local config = require("fsbookmark.config")
local util = require("fsbookmark.util")

local M = {}

M.group = nil

---@type table<string, fun(): string|nil>
M.providers = {}

--- Snacks explorer is a picker; the focused item carries the path.
function M.providers.snacks()
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    return nil
  end
  local picker = (Snacks.picker.get({ source = "explorer" }) or {})[1]
  if not picker then
    return nil
  end

  -- `picker:current()` is the authority. A window cursor row is NOT an item
  -- index — Snacks renders a scrolled window over the item list and converts
  -- with `row2idx(row - topline + 1)` — so reading the row directly picks the
  -- wrong entry as soon as the tree is scrolled.
  local item = picker:current()
  return item and (item.file or item._path) or nil
end

M.providers["neo-tree"] = function()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok or not manager.get_state_for_window then
    return nil
  end
  local state = manager.get_state_for_window(vim.api.nvim_get_current_win())
  local node = state and state.tree and state.tree:get_node()
  return node and node:get_id() or nil
end

function M.providers.oil()
  local ok, oil = pcall(require, "oil")
  if not ok then
    return nil
  end
  local entry = oil.get_cursor_entry()
  local dir = oil.get_current_dir()
  if not entry or not dir then
    return nil
  end
  return dir .. entry.name
end

--- Path under the cursor in whichever explorer is focused, else the buffer path.
---@return string|nil
function M.current_path()
  local filetype = vim.bo.filetype
  local by_filetype = {
    snacks_picker_list = "snacks",
    snacks_picker_input = "snacks",
    ["neo-tree"] = "neo-tree",
    oil = "oil",
  }

  local provider = M.providers[by_filetype[filetype] or ""]
  if provider then
    local path = provider()
    if path then
      return util.normalize(path)
    end
  end

  local name = vim.api.nvim_buf_get_name(0)
  return name ~= "" and util.normalize(name) or nil
end

--- Toggle the bookmark for the path under the cursor.
---@return boolean added
function M.toggle()
  local fsbookmark = require("fsbookmark")
  local path = M.current_path()
  if not path then
    util.notify("no path under cursor", vim.log.levels.WARN)
    return false
  end

  local added = fsbookmark.toggle(path)
  local icons = config.options.icons
  util.notify((added and icons.bookmark .. " added " or "removed ") .. util.display_path(path))
  M.refresh()
  return added
end

--- Ask the focused explorer to redraw so the marker updates.
function M.refresh()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker then
    for _, picker in ipairs(Snacks.picker.get({ source = "explorer" }) or {}) do
      -- `list:update()`/`list:render()` reuse the rendered rows, so the
      -- bookmark marker would not appear until the explorer was reopened.
      -- Only re-running the finder re-formats the tree — and that resets the
      -- cursor to the top unless the current position is pinned first, which
      -- is what Snacks' own explorer actions do around their refreshes.
      pcall(function()
        picker.list:set_target()
        picker:find()
      end)
    end
  end

  if package.loaded["neo-tree.sources.manager"] then
    pcall(vim.cmd, "Neotree refresh")
  end
end

--- Open a directory in the best available explorer.
---@param path string
function M.open_directory(path)
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.explorer then
    return Snacks.explorer({ cwd = path })
  end
  if package.loaded["oil"] or pcall(require, "oil") then
    return require("oil").open(path)
  end
  if pcall(require, "neo-tree.command") then
    return require("neo-tree.command").execute({ action = "focus", dir = path })
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Drop-in `format` for the Snacks explorer source that prefixes bookmarked
--- entries with the bookmark icon. Snacks has no chaining hook for decorations,
--- so this is last-writer-wins with any other plugin overriding the format.
---@param item table
---@param picker table
---@return table[]
function M.format(item, picker)
  local Snacks = require("snacks")
  local out = Snacks.picker.format.file(item, picker)

  local bookmark = item.file and require("fsbookmark").get(item.file)
  if bookmark then
    -- `virtual` keeps the marker out of the matcher's text.
    table.insert(out, 1, { config.options.icons.bookmark, "SnacksPickerLabel", virtual = true })
    table.insert(out, 2, { " ", virtual = true })
  end

  return out
end

--- Register the toggle keymap in explorer buffers.
function M.setup()
  local key = config.options.explorer.key
  if not key then
    return
  end
  if M.group then
    return
  end
  M.group = vim.api.nvim_create_augroup("fsbookmark_explorer", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = M.group,
    pattern = { "snacks_picker_list", "neo-tree", "oil" },
    callback = function(args)
      vim.keymap.set("n", key, M.toggle, {
        buffer = args.buf,
        desc = "Toggle bookmark",
        nowait = true,
      })
    end,
  })
end

return M
