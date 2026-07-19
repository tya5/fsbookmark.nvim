# fsbookmark.nvim

Bookmarks for files and directories, with metadata.

Not a "recently used files" list — a workspace navigation layer. Every bookmark
carries a description and free-form labels, and everything is fuzzy-searchable
from one picker.

This plugin ships almost no UI of its own. It leans on
[snacks.nvim](https://github.com/folke/snacks.nvim) for the picker and explorer,
and `vim.ui.input` for editing.

```
★ runtime.py    Runtime scheduler    core runtime hot    src/runtime.py
★ src           Sources              core ssd            src
⚠ removed.py                                             old/removed.py
```

## Requirements

- Neovim >= 0.10
- [snacks.nvim](https://github.com/folke/snacks.nvim) with `picker` enabled (for `picker()` only — the API works without it)

## Installation

### lazy.nvim

```lua
{
  "tya5/fsbookmark.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = {
    { "<leader>ma", function() require("fsbookmark").add() end, desc = "Add bookmark" },
    { "<leader>mf", function() require("fsbookmark").picker() end, desc = "Find bookmarks" },
    { "<leader>mt", function() require("fsbookmark").toggle() end, desc = "Toggle bookmark" },
    { "<leader>me", function() require("fsbookmark").edit() end, desc = "Edit bookmark" },
    { "<leader>mr", function() require("fsbookmark").remove() end, desc = "Remove bookmark" },
  },
}
```

`opts = {}` is enough — lazy.nvim calls `setup()` for you, which also registers
the default keymaps. If you define your own `keys` as above, set
`opts = { keys = { enabled = false } }` to avoid registering them twice.

### LazyVim

The defaults are already LazyVim-shaped, with one deliberate choice: the keymap
prefix is **`<leader>m`, not `<leader>b`**. LazyVim owns `<leader>b` as its
buffer group, and which-key auto-expands buffer-local maps into it.

To also get `Snacks.picker.fsbookmark()` and a `★` marker in the Snacks
explorer:

```lua
{
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        fsbookmark = function() return require("fsbookmark.picker").source() end,
        explorer = {
          format = function(item, picker) return require("fsbookmark.explorer").format(item, picker) end,
          win = { list = { keys = { ["mb"] = "fsbookmark_toggle" } } },
          actions = {
            fsbookmark_toggle = function() require("fsbookmark.explorer").toggle() end,
          },
        },
      },
    },
  },
},
{
  "folke/which-key.nvim",
  optional = true,
  opts = { spec = { { "<leader>m", group = "bookmarks", icon = "★" } } },
},
```

Without registering the source, `Snacks.picker.fsbookmark` is `nil` — Snacks only
exposes named pickers it knows about. `require("fsbookmark").picker()` always works.

## Usage

| Keymap        | Action           |
| ------------- | ---------------- |
| `<leader>ma`  | Add bookmark     |
| `<leader>mf`  | Find bookmarks   |
| `<leader>mt`  | Toggle bookmark  |
| `<leader>me`  | Edit bookmark    |
| `<leader>mr`  | Remove bookmark  |
| `mb`          | Toggle (in an explorer buffer) |

Also `:FSBookmark {add,remove,toggle,edit,list,prune,save,load} [path]`.

### Picker

| Key      | Action        |
| -------- | ------------- |
| `<CR>`   | Open          |
| `<C-e>`  | Edit          |
| `<C-d>`  | Delete        |
| `<C-r>`  | Reload        |
| `<C-y>`  | Copy path     |
| `<C-b>`  | Reveal in explorer |

`<C-d>` respects multi-selection.

The picker runs as a `live` Snacks source, so the prompt is handed to this
plugin's own parser rather than to the built-in matcher — `label:core` typed
into the picker means the same thing as it does in `search()`.

### Search

Path, description and labels are all fuzzy-matched. Multiple terms are ANDed.

```
runtime            -- anything matching "runtime"
runtime hot        -- both terms must match
label:core         -- only bookmarks labelled "core"
label:core label:ssd
label:core scheduler
```

The path is fuzzy-matched on its basename and substring-matched on the full
path — scattered subsequence matching over an absolute path matches everything.

### Editing

No custom edit UI. `edit()` prompts through `vim.ui.input` twice:

```
Description: Runtime scheduler
Labels (csv): core,runtime,hot
```

Cancelling either prompt aborts the edit. Editing an unregistered path registers
it first.

## API

```lua
local fsbookmark = require("fsbookmark")

fsbookmark.add(path?, { description = "...", labels = { "core" } })  --> bookmark, created
fsbookmark.remove(path?)                                            --> bookmark|nil
fsbookmark.toggle(path?)                                            --> boolean (added?)
fsbookmark.get(path?)                                               --> bookmark|nil
fsbookmark.list()                                                   --> bookmark[]
fsbookmark.search(query)                                            --> bookmark[]
fsbookmark.update(path, { description = ..., labels = ... })        --> bookmark|nil
fsbookmark.labels()                                                 --> string[]
fsbookmark.is_broken(bookmark)                                      --> boolean
fsbookmark.open(bookmark|path)
fsbookmark.picker(opts?)
fsbookmark.edit(path?, on_done?)
fsbookmark.save()
fsbookmark.load()
```

`path` defaults to the current buffer everywhere. Paths are normalized
(absolute, `~` expanded, no trailing slash) before use, so any spelling of the
same path hits the same bookmark.

### Bookmark

```lua
{
  id = "...",
  path = "/abs/path",
  type = "file" | "directory",
  description = "",
  labels = { "core", "runtime" },
  scope = "global",   -- reserved for per-workspace bookmarks
  metadata = {},      -- free-form; for other plugins and future fields
  created_at = 1721000000,
  updated_at = 1721000000,
}
```

### Events

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = { "FSBookmarkAdd", "FSBookmarkRemove", "FSBookmarkUpdate" },
  callback = function(args)
    vim.print(args.data.path)  -- the bookmark
  end,
})
```

## Configuration

Defaults:

```lua
require("fsbookmark").setup({
  file = nil,        -- defaults to stdpath("data")/fsbookmark/bookmarks.json
  autosave = true,
  watch = true,      -- follow renames; flag missing paths as broken
  icons = { bookmark = "★", broken = "⚠", directory = "", file = "" },
  picker = {
    keys = { edit = "<c-e>", delete = "<c-d>", reload = "<c-r>", yank = "<c-y>" },
  },
  explorer = { enabled = true, key = "mb" },
  keys = { enabled = true, prefix = "<leader>m" },
  open_directory = nil,  -- fun(path); defaults to Snacks explorer / oil / neo-tree
})
```

## Storage

```
stdpath("data")/fsbookmark/bookmarks.json
```

```json
{ "version": 1, "bookmarks": [ ... ] }
```

Written atomically (temp file + rename). A corrupt file is reported and treated
as empty rather than crashing — it is never overwritten until you change
something. The envelope leaves room for the planned per-workspace split
(`global.json` + `workspace/*.json`).

## Broken bookmarks

A bookmark whose path no longer exists is shown as `⚠` rather than being deleted
behind your back. Renames performed inside Neovim (`:saveas`, Snacks/oil rename)
are followed automatically. `:FSBookmark prune` removes all broken ones.

## Explorer integration

`require("fsbookmark.explorer").toggle()` bookmarks the path under the cursor.
It knows how to read the cursor path from the Snacks explorer, neo-tree and oil,
and falls back to the current buffer's file.

The `★` marker in the Snacks explorer needs the `format` override shown above.
Snacks has no chaining hook for third-party decorations, so that override is
last-writer-wins with any other plugin doing the same.

## Troubleshooting

Run `:checkhealth fsbookmark` first — it covers every failure below.

| Symptom | Cause |
| ------- | ----- |
| `:FSBookmark` is not a command | The plugin directory isn't on `runtimepath`. |
| Keymaps do nothing | `setup()` was never called. With lazy.nvim, add `opts = {}`. |
| `<leader>m…` does nothing | Another plugin already owns the mapping — it is never clobbered. Change `keys.prefix`, or set `keys.enabled = false` and map it yourself. |
| `Snacks.picker.fsbookmark` is nil | The source isn't registered under `picker.sources`. `require("fsbookmark").picker()` works either way. |
| "snacks.nvim with the picker enabled is required" | snacks is missing, or its picker is disabled. |
| Bookmarks don't persist | The data directory isn't writable, or `autosave = false` and Neovim was killed rather than exited. |
| A file got bookmarked twice | Shouldn't happen — paths are normalized and symlinks resolved. Please open an issue with both paths. |

Nothing here overwrites your data: a corrupt `bookmarks.json` is reported and
treated as empty, and is left on disk untouched until you change something.

## Not in scope

Custom TUI, custom picker, SQLite, git/cloud sync, tag hierarchies, tree view.

## License

MIT
