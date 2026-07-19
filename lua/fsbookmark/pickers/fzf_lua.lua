local entry = require("fsbookmark.entry")
local util = require("fsbookmark.util")

--- fzf-lua backend.
---
--- Uses `fzf_live` so each keystroke goes through `fsbookmark.search()` rather
--- than fzf's own matcher, keeping `label:` and `scope:` working. The path is
--- appended after a NUL-ish separator so it can be recovered on select without
--- being part of what the user reads.
local M = {}

local SEP = " \1 "

---@param opts table|nil
function M.open(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    util.notify("fzf-lua is not installed", vim.log.levels.ERROR)
    return
  end

  local fsbookmark = require("fsbookmark")
  local _, workspace_name = fsbookmark.workspace()

  ---@param line string
  ---@return string|nil
  local function path_of(line)
    return line and line:match("\1 (.*)$") or nil
  end

  -- fzf-lua hands the live callback a table, with the current query at [1] —
  -- not the query string itself.
  fzf.fzf_live(function(args)
    local query = type(args) == "table" and args[1] or args
    local lines = {}
    for _, item in ipairs(entry.list(query)) do
      table.insert(lines, item.line .. SEP .. item.bookmark.path)
    end
    return lines
  end, vim.tbl_deep_extend("force", {
    prompt = (workspace_name and ("Bookmarks (%s)"):format(workspace_name) or "Bookmarks") .. "> ",
    -- Hide the trailing path field from view; it is only there to identify
    -- the selection.
    fzf_opts = { ["--delimiter"] = "\1", ["--with-nth"] = "1" },
    actions = {
      ["default"] = function(selected)
        local path = path_of(selected and selected[1])
        if path then
          fsbookmark.open(path)
        end
      end,
      ["ctrl-e"] = function(selected)
        local path = path_of(selected and selected[1])
        if path then
          fsbookmark.edit(path)
        end
      end,
      ["ctrl-x"] = function(selected)
        for _, line in ipairs(selected or {}) do
          local path = path_of(line)
          if path then
            fsbookmark.remove(path)
          end
        end
      end,
      ["ctrl-y"] = function(selected)
        local path = path_of(selected and selected[1])
        if path then
          vim.fn.setreg("+", path)
          util.notify("copied " .. path)
        end
      end,
    },
  }, opts or {}))
end

return M
