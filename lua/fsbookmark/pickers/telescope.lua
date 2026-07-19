local entry = require("fsbookmark.entry")
local util = require("fsbookmark.util")

--- Telescope backend.
---
--- Telescope's own sorter is bypassed: the prompt goes straight to
--- `fsbookmark.search()` so `label:` and `scope:` mean the same thing here as
--- everywhere else. That is what a dynamic finder is for.
local M = {}

---@param opts table|nil
function M.open(opts)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    util.notify("telescope.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  local fsbookmark = require("fsbookmark")
  local _, workspace_name = fsbookmark.workspace()

  local function make_entry(item)
    return {
      value = item.bookmark,
      display = item.line,
      ordinal = item.line,
      path = item.bookmark.path,
    }
  end

  local finder = finders.new_dynamic({
    fn = function(prompt)
      return entry.list(prompt)
    end,
    entry_maker = make_entry,
  })

  pickers
    .new(opts or {}, {
      prompt_title = workspace_name and ("Bookmarks (%s)"):format(workspace_name) or "Bookmarks",
      finder = finder,
      -- The query language already ranked these; re-sorting would fight it.
      sorter = sorters.empty(),
      previewer = conf.file_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selected then
            fsbookmark.open(selected.value)
          end
        end)

        local function refresh(picker_bufnr)
          local picker = action_state.get_current_picker(picker_bufnr)
          picker:refresh(finder, { reset_prompt = false })
        end

        map({ "i", "n" }, "<c-e>", function(bufnr)
          local selected = action_state.get_selected_entry()
          if selected then
            fsbookmark.edit(selected.value.path, function()
              refresh(bufnr)
            end)
          end
        end)

        map({ "i", "n" }, "<c-x>", function(bufnr)
          local selected = action_state.get_selected_entry()
          if selected then
            fsbookmark.remove(selected.value.path)
            refresh(bufnr)
          end
        end)

        map({ "i", "n" }, "<c-y>", function()
          local selected = action_state.get_selected_entry()
          if selected then
            vim.fn.setreg("+", selected.value.path)
            util.notify("copied " .. selected.value.path)
          end
        end)

        return true
      end,
    })
    :find()
end

return M
