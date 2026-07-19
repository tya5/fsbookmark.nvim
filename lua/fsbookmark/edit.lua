local util = require("fsbookmark.util")

local M = {}

--- Prompt for description, then labels. Cancelling either step aborts the edit.
---@param path string|nil defaults to the current buffer
---@param on_done fun(bookmark: Bookmark|nil)|nil
function M.edit(path, on_done)
  local fsbookmark = require("fsbookmark")
  on_done = on_done or function() end

  local bookmark = fsbookmark.get(path)
  if not bookmark then
    -- Editing an unregistered path registers it first, which is what users mean.
    bookmark = select(1, fsbookmark.add(path))
  end
  if not bookmark then
    util.notify("no path to edit", vim.log.levels.WARN)
    return on_done(nil)
  end

  local target = bookmark.path

  vim.ui.input({
    prompt = "Description: ",
    default = bookmark.description or "",
  }, function(description)
    if description == nil then
      return on_done(nil)
    end

    vim.ui.input({
      prompt = "Labels (csv): ",
      default = table.concat(bookmark.labels or {}, ","),
    }, function(labels)
      if labels == nil then
        return on_done(nil)
      end

      on_done(fsbookmark.update(target, {
        description = vim.trim(description),
        labels = util.parse_csv(labels),
      }))
    end)
  end)
end

return M
