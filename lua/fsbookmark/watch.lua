local store = require("fsbookmark.store")
local util = require("fsbookmark.util")

local M = {}

M.group = nil

--- Follow a rename so the bookmark keeps pointing at the moved file.
---@param from string
---@param to string
function M.on_rename(from, to)
  local events = require("fsbookmark.events")
  local bookmark = store.rekey(from, to)
  if bookmark then
    store.touch()
    events.emit(events.UPDATE, bookmark)
  end
end

--- Watch for renames performed through Neovim. Deletions are not tracked
--- eagerly — a missing path is reported as broken when it is next displayed.
function M.setup()
  if M.group then
    return
  end
  M.group = vim.api.nvim_create_augroup("fsbookmark_watch", { clear = true })

  -- `:saveas` / `:file` move the buffer; keep the bookmark attached to it.
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = M.group,
    callback = function(args)
      local to = vim.api.nvim_buf_get_name(args.buf)
      if args.file ~= "" and to ~= "" then
        M.on_rename(util.normalize(args.file), util.normalize(to))
      end
    end,
  })

  -- LSP-driven renames (`vim.lsp.util.rename` fires this via Snacks/oil too).
  vim.api.nvim_create_autocmd("User", {
    group = M.group,
    pattern = { "SnacksRename", "NvimTreeSetup", "OilActionsPost" },
    callback = function(args)
      local data = args.data or {}
      if data.from and data.to then
        M.on_rename(data.from, data.to)
      end
    end,
  })
end

--- Bookmarks whose path no longer exists.
---@return Bookmark[]
function M.broken()
  store.ensure()
  return vim.tbl_filter(function(bookmark)
    return not util.exists(bookmark.path)
  end, store.items)
end

--- Drop every broken bookmark.
---@return integer removed
function M.prune()
  local fsbookmark = require("fsbookmark")
  local removed = 0
  for _, bookmark in ipairs(M.broken()) do
    if fsbookmark.remove(bookmark.path) then
      removed = removed + 1
    end
  end
  return removed
end

return M
