if vim.g.loaded_fsbookmark then
  return
end
vim.g.loaded_fsbookmark = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("fsbookmark.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
  return
end

local subcommands = {
  add = function(args)
    require("fsbookmark").add(args[1])
  end,
  remove = function(args)
    require("fsbookmark").remove(args[1])
  end,
  toggle = function(args)
    require("fsbookmark").toggle(args[1])
  end,
  edit = function(args)
    require("fsbookmark").edit(args[1])
  end,
  list = function()
    require("fsbookmark").picker()
  end,
  prune = function()
    local removed = require("fsbookmark.watch").prune()
    require("fsbookmark.util").notify(("removed %d broken bookmark(s)"):format(removed))
  end,
  save = function()
    require("fsbookmark").save()
  end,
  load = function()
    require("fsbookmark").load()
  end,
}

vim.api.nvim_create_user_command("FSBookmark", function(opts)
  local args = opts.fargs
  local name = table.remove(args, 1) or "list"
  local run = subcommands[name]
  if not run then
    vim.notify("unknown subcommand: " .. name, vim.log.levels.ERROR, { title = "fsbookmark" })
    return
  end
  run(args)
end, {
  nargs = "*",
  complete = function(lead)
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, vim.tbl_keys(subcommands))
  end,
  desc = "fsbookmark.nvim",
})

-- Flush pending changes when autosave is off.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("fsbookmark_exit", { clear = true }),
  callback = function()
    local store = package.loaded["fsbookmark.store"]
    if store and store.dirty() then
      store.save()
    end
  end,
})
