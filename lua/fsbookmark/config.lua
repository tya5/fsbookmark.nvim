local M = {}

---@class FSBookmarkConfig
local defaults = {
  -- Where bookmarks are persisted. Defaults to
  -- stdpath("data")/fsbookmark/bookmarks, holding global.json and workspace/.
  ---@type string|nil
  dir = nil,

  workspace = {
    -- Resolve a workspace root and keep its bookmarks in a separate file.
    -- With this off, everything lives in global.json.
    enabled = true,
  },

  -- Save to disk automatically after every mutation.
  autosave = true,

  -- Track renames/deletes so broken bookmarks can be surfaced.
  watch = true,

  icons = {
    bookmark = "★",
    broken = "⚠",
    directory = "",
    file = "",
    global = "🌍",
    workspace = "📁",
  },

  picker = {
    -- Snacks picker keymaps. Set a value to false to disable it.
    keys = {
      edit = "<c-e>",
      delete = "<c-d>",
      reload = "<c-r>",
      yank = "<c-y>",
      -- `<c-s>`/`<c-v>`/`<c-t>` are Snacks' split/vsplit/tab actions.
      reveal = "<c-b>",
    },
  },

  explorer = {
    -- Register the toggle keymap in supported explorer buffers.
    enabled = true,
    key = "mb",
  },

  keys = {
    -- Register the which-key group. Set `enabled = false` to opt out entirely.
    enabled = true,
    -- `<leader>m` rather than `<leader>b`: LazyVim already owns `<leader>b`
    -- as its buffer group, and which-key auto-expands buffer-local maps into it.
    prefix = "<leader>m",
  },

  -- How directories are opened from the picker.
  ---@type fun(path: string)|nil
  open_directory = nil,
}

---@type FSBookmarkConfig
M.options = vim.deepcopy(defaults)

M.defaults = defaults

-- Whether setup() ran. Surfaced by `:checkhealth fsbookmark`.
M.configured = false

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  M.configured = true
  return M.options
end

---@return string
function M.dir()
  return M.options.dir or vim.fs.joinpath(vim.fn.stdpath("data"), "fsbookmark", "bookmarks")
end

return M
