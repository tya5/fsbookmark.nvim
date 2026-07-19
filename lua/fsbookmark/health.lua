local config = require("fsbookmark.config")
local store = require("fsbookmark.store")

local M = {}

local health = vim.health

local function check_nvim()
  health.start("Neovim")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.10 is required")
  end
end

local function check_setup()
  health.start("Setup")
  if vim.g.loaded_fsbookmark then
    health.ok("plugin/fsbookmark.lua loaded (:FSBookmark available)")
  else
    health.error("plugin/fsbookmark.lua was not sourced", {
      "Check that the plugin directory is on your 'runtimepath'.",
      "With lazy.nvim, make sure the spec name matches the repository.",
    })
  end

  if config.configured then
    health.ok("setup() was called")
  else
    health.warn("setup() has not been called — keymaps are not registered", {
      "With lazy.nvim add `opts = {}` to the spec; it calls setup() for you.",
      "The Lua API works regardless.",
    })
  end
end

local function check_snacks()
  health.start("Picker (snacks.nvim)")
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    health.warn("snacks.nvim not found — picker() is unavailable", {
      "Install folke/snacks.nvim, or use the Lua API directly.",
    })
    return
  end
  if not Snacks.picker then
    health.warn("snacks.nvim is installed but the picker is disabled", {
      'Enable it with `opts = { picker = { enabled = true } }`.',
    })
    return
  end
  health.ok("snacks.picker available")

  local queried, registered = pcall(function()
    return Snacks.config.get("picker", {}).sources.fsbookmark ~= nil
  end)
  if queried and registered then
    health.ok("source registered — Snacks.picker.fsbookmark() works")
  else
    health.info("source not registered under picker.sources — use require('fsbookmark').picker()")
  end
end

local function check_storage()
  health.start("Storage")
  local path = config.file()
  local dir = vim.fs.dirname(path)

  if vim.fn.isdirectory(dir) == 0 then
    health.info(dir .. " does not exist yet (created on first save)")
  elseif vim.fn.filewritable(dir) ~= 2 then
    health.error(dir .. " is not writable — bookmarks cannot be saved")
  else
    health.ok(dir .. " is writable")
  end

  if not vim.uv.fs_stat(path) then
    health.info(path .. " does not exist yet")
    return
  end

  if store.load() then
    health.ok(("%s — %d bookmark(s)"):format(path, #store.items))
  else
    health.error(path .. " could not be parsed", {
      "Fix or delete the file. It is not overwritten until you change something.",
    })
    return
  end

  local broken = require("fsbookmark.watch").broken()
  if #broken > 0 then
    health.warn(("%d bookmark(s) point at a missing path"):format(#broken), {
      "Run `:FSBookmark prune` to remove them.",
    })
  end
end

local function check_conflicts()
  health.start("Keymaps")
  if not config.options.keys.enabled or not config.options.keys.prefix then
    health.info("keymap registration is disabled")
    return
  end

  local prefix = config.options.keys.prefix
  local clashes = {}
  for _, key in ipairs(require("fsbookmark.keys").spec()) do
    local lhs = vim.fn.keytrans(vim.api.nvim_replace_termcodes(prefix .. key.suffix, true, true, true))
    local existing = vim.fn.maparg(prefix .. key.suffix, "n", false, true)
    if existing and existing.desc and existing.desc ~= key.desc then
      table.insert(clashes, ("%s is mapped to %q"):format(lhs, existing.desc))
    end
  end

  if #clashes == 0 then
    health.ok("no conflicts under " .. prefix)
  else
    health.warn("keymaps owned by another plugin were left alone:\n" .. table.concat(clashes, "\n"), {
      "Set `keys = { prefix = '<leader>M' }`, or `keys = { enabled = false }` and map them yourself.",
    })
  end
end

function M.check()
  check_nvim()
  check_setup()
  check_snacks()
  check_storage()
  check_conflicts()
end

return M
