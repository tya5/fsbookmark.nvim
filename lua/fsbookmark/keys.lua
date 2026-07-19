local config = require("fsbookmark.config")

local M = {}

--- Keymaps registered under `config.keys.prefix`.
---@return table[]
function M.spec()
  local fsbookmark = require("fsbookmark")
  return {
    {
      suffix = "a",
      desc = "Add bookmark",
      rhs = function()
        fsbookmark.add()
      end,
    },
    {
      suffix = "f",
      desc = "Find bookmarks",
      rhs = function()
        fsbookmark.picker()
      end,
    },
    {
      suffix = "t",
      desc = "Toggle bookmark",
      rhs = function()
        fsbookmark.toggle()
      end,
    },
    {
      suffix = "e",
      desc = "Edit bookmark",
      rhs = function()
        fsbookmark.edit()
      end,
    },
    {
      suffix = "r",
      desc = "Remove bookmark",
      rhs = function()
        fsbookmark.remove()
      end,
    },
  }
end

function M.setup()
  local prefix = config.options.keys.prefix
  if not prefix then
    return
  end

  for _, key in ipairs(M.spec()) do
    local lhs = prefix .. key.suffix
    -- Never clobber a mapping the user (or another plugin) already owns;
    -- `:checkhealth fsbookmark` reports whatever was skipped.
    if vim.fn.maparg(lhs, "n") == "" then
      vim.keymap.set("n", lhs, key.rhs, { desc = key.desc })
    end
  end

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({ { prefix, group = "Bookmarks", icon = config.options.icons.bookmark } })
  end
end

return M
