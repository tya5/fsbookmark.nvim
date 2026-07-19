local util = require("fsbookmark.util")

local M = {}

--- Completion for the CSV labels prompt: completes the token after the last
--- comma against the labels already in use.
---@param lead string
---@param line string
---@return string[]
function M.complete_labels(lead, line)
  local prefix, token = (line or ""):match("^(.*,)%s*([^,]*)$")
  if not prefix then
    prefix, token = "", line or ""
  end
  token = vim.trim(token)

  -- Labels already on the line are not candidates; offering them again just
  -- proposes a duplicate that `parse_csv` would drop anyway.
  local taken = {}
  for _, label in ipairs(util.parse_csv(prefix)) do
    taken[label:lower()] = true
  end

  local out = {}
  for _, label in ipairs(require("fsbookmark").labels()) do
    if not taken[label:lower()] and vim.startswith(label:lower(), token:lower()) then
      table.insert(out, prefix .. label)
    end
  end

  -- `lead` is unused: with a CSV prompt the whole line is the completion unit.
  local _ = lead
  return out
end

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
      completion = "customlist,v:lua.require'fsbookmark.edit'.complete_labels",
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
