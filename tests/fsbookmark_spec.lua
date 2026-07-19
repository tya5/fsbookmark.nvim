local fsbookmark = require("fsbookmark")
local search = require("fsbookmark.search")
local store = require("fsbookmark.store")

local tmpdir, file_a, file_b, dir_a

local function reset()
  tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")

  file_a = tmpdir .. "/runtime.py"
  file_b = tmpdir .. "/scheduler.md"
  dir_a = tmpdir .. "/src"
  vim.fn.writefile({ "" }, file_a)
  vim.fn.writefile({ "" }, file_b)
  vim.fn.mkdir(dir_a, "p")

  -- Bookmarks are keyed by the normalized path, and on macOS the temp dir is
  -- reached through a symlink (/var -> /private/var). Compare like for like.
  local normalize = require("fsbookmark.util").normalize
  tmpdir, file_a, file_b, dir_a = normalize(tmpdir), normalize(file_a), normalize(file_b), normalize(dir_a)

  fsbookmark.setup({
    dir = tmpdir .. "/bookmarks",
    -- Most specs exercise the single-file behaviour; the workspace block below
    -- re-runs setup with it on.
    workspace = { enabled = false },
    watch = false,
    explorer = { enabled = false },
    keys = { enabled = false },
  })
end

--- Path of the global collection on disk, with its directory created so specs
--- can write a fixture there before anything has been saved.
local function global_file()
  local path = store.file("global")
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  return path
end

describe("api", function()
  before_each(reset)

  it("adds a file and reports its type", function()
    local bookmark, created = fsbookmark.add(file_a)
    assert.is_true(created)
    assert.equals("file", bookmark.type)
    assert.equals(1, #fsbookmark.list())
  end)

  it("detects directories", function()
    assert.equals("directory", fsbookmark.add(dir_a).type)
  end)

  it("is idempotent on add", function()
    local first = fsbookmark.add(file_a)
    local second, created = fsbookmark.add(file_a)
    assert.is_false(created)
    assert.equals(first.id, second.id)
    assert.equals(1, #fsbookmark.list())
  end)

  it("normalizes paths so trailing slashes match", function()
    fsbookmark.add(dir_a)
    assert.is_not_nil(fsbookmark.get(dir_a .. "/"))
  end)

  it("toggles both ways", function()
    assert.is_true(fsbookmark.toggle(file_a))
    assert.is_not_nil(fsbookmark.get(file_a))
    assert.is_false(fsbookmark.toggle(file_a))
    assert.is_nil(fsbookmark.get(file_a))
  end)

  it("updates description and labels", function()
    fsbookmark.add(file_a)
    local updated = fsbookmark.update(file_a, {
      description = "Runtime scheduler",
      labels = { "core", "runtime" },
    })
    assert.equals("Runtime scheduler", updated.description)
    assert.same({ "core", "runtime" }, updated.labels)
  end)

  it("returns nil when updating an unknown path", function()
    assert.is_nil(fsbookmark.update(file_a, { description = "x" }))
  end)

  it("collects labels in use", function()
    fsbookmark.add(file_a, { labels = { "runtime", "core" } })
    fsbookmark.add(file_b, { labels = { "core" } })
    assert.same({ "core", "runtime" }, fsbookmark.labels())
  end)

  it("stamps the reserved scope and source fields", function()
    local bookmark = fsbookmark.add(file_a)
    assert.equals("global", bookmark.scope)
    assert.equals("manual", bookmark.source)
    assert.same({}, bookmark.metadata)
  end)

  it("defaults scope and source when reading an older file", function()
    -- A file written before these fields existed.
    vim.fn.writefile({
      vim.json.encode({
        version = 1,
        bookmarks = { { path = file_a, description = "old", labels = {} } },
      }),
    }, global_file())

    fsbookmark.load()
    local bookmark = fsbookmark.get(file_a)
    assert.equals("global", bookmark.scope)
    assert.equals("manual", bookmark.source)
    assert.equals("old", bookmark.description)
  end)

  it("flags missing paths as broken", function()
    local bookmark = fsbookmark.add(file_a)
    assert.is_false(fsbookmark.is_broken(bookmark))
    vim.fn.delete(file_a)
    assert.is_true(fsbookmark.is_broken(bookmark))
  end)
end)

describe("persistence", function()
  before_each(reset)

  it("round-trips through json", function()
    fsbookmark.add(file_a, { description = "Runtime", labels = { "core" } })
    fsbookmark.save()
    fsbookmark.load()

    local bookmark = fsbookmark.get(file_a)
    assert.is_not_nil(bookmark)
    assert.equals("Runtime", bookmark.description)
    assert.same({ "core" }, bookmark.labels)
  end)

  it("reloads in place without dropping entries as duplicates", function()
    fsbookmark.add(file_a)
    fsbookmark.add(file_b)
    fsbookmark.save()

    -- Reloading over a populated store must rebuild the index, not dedupe
    -- against it. This is what the picker's reload action does.
    fsbookmark.load()
    assert.equals(2, #fsbookmark.list())
    assert.is_not_nil(fsbookmark.get(file_a))
  end)

  it("keeps only the first entry when the file has duplicate paths", function()
    vim.fn.writefile({
      vim.json.encode({
        version = 1,
        bookmarks = {
          { path = file_a, description = "first", labels = {} },
          { path = file_a, description = "second", labels = {} },
        },
      }),
    }, global_file())

    fsbookmark.load()
    assert.equals(1, #fsbookmark.list())
    assert.equals("first", fsbookmark.get(file_a).description)
  end)

  it("writes a versioned envelope", function()
    fsbookmark.add(file_a)
    fsbookmark.save()
    local decoded = vim.json.decode(table.concat(vim.fn.readfile(global_file()), "\n"))
    assert.equals(store.SCHEMA_VERSION, decoded.version)
    assert.equals(1, #decoded.bookmarks)
  end)

  it("survives a corrupt file", function()
    vim.fn.writefile({ "{ not json" }, global_file())
    assert.is_false(fsbookmark.load())
    assert.same({}, fsbookmark.list())
  end)

  it("starts empty when no file exists", function()
    assert.is_true(fsbookmark.load())
    assert.same({}, fsbookmark.list())
  end)
end)

describe("search", function()
  before_each(function()
    reset()
    fsbookmark.add(file_a, { description = "Runtime scheduler", labels = { "core", "runtime", "hot" } })
    fsbookmark.add(file_b, { description = "Design notes", labels = { "design" } })
    fsbookmark.add(dir_a, { description = "Sources", labels = { "core", "ssd" } })
  end)

  it("returns everything for an empty query", function()
    assert.equals(3, #fsbookmark.search(""))
  end)

  it("matches on path", function()
    local found = fsbookmark.search("runtime.py")
    assert.equals(1, #found)
    assert.equals(file_a, found[1].path)
  end)

  it("matches on description", function()
    local found = fsbookmark.search("Design")
    assert.equals(1, #found)
    assert.equals(file_b, found[1].path)
  end)

  it("does not fuzzy-match scattered letters across a long path", function()
    -- The absolute tmpdir would otherwise match almost any query.
    assert.equals(0, #fsbookmark.search("zqxj"))
  end)

  it("ANDs multiple terms", function()
    assert.equals(1, #fsbookmark.search("runtime hot"))
    assert.equals(0, #fsbookmark.search("runtime design"))
  end)

  it("filters by label", function()
    assert.equals(2, #fsbookmark.search("label:core"))
    assert.equals(1, #fsbookmark.search("label:core label:ssd"))
    assert.equals(0, #fsbookmark.search("label:nope"))
  end)

  it("combines labels and free text", function()
    local found = fsbookmark.search("label:core scheduler")
    assert.equals(1, #found)
    assert.equals(file_a, found[1].path)
  end)

  it("matches fuzzily", function()
    assert.equals(1, #search.filter(store.items, "rntm"))
  end)

  it("ranks exact substrings above scattered matches", function()
    local found = search.filter(store.items, "design")
    assert.equals(file_b, found[1].path)
  end)
end)

describe("picker source", function()
  local function find(query)
    -- Mirrors how Snacks invokes a `live` finder.
    local source = require("fsbookmark.picker").source()
    return source.finder({}, { filter = { search = query } })
  end

  before_each(function()
    reset()
    fsbookmark.add(file_a, { description = "Runtime scheduler", labels = { "core", "hot" } })
    fsbookmark.add(file_b, { description = "Design notes", labels = { "design" } })
  end)

  it("runs live so the finder owns the prompt", function()
    local source = require("fsbookmark.picker").source()
    assert.is_true(source.live)
    assert.is_true(source.show_empty)
  end)

  it("routes the prompt through fsbookmark.search", function()
    assert.equals(2, #find(""))
    local found = find("Design")
    assert.equals(1, #found)
    assert.equals(file_b, found[1].bookmark.path)
  end)

  it("honours label: filters typed into the picker", function()
    local found = find("label:core")
    assert.equals(1, #found)
    assert.equals(file_a, found[1].bookmark.path)
    assert.equals(0, #find("label:nope"))
  end)

  it("gives every item a non-nil text field", function()
    for _, item in ipairs(find("")) do
      assert.is_string(item.text)
      assert.is_true(#item.text > 0)
    end
  end)

  it("returns items in ranked order", function()
    -- The matcher is inert under `live`, so finder order is display order.
    local found = find("design")
    assert.equals(file_b, found[1].bookmark.path)
  end)
end)

describe("workspace", function()
  local ws_root, inside, outside

  local function setup_workspace()
    reset()
    ws_root = tmpdir .. "/proj"
    vim.fn.mkdir(ws_root .. "/.git", "p")
    inside = ws_root .. "/main.lua"
    outside = tmpdir .. "/elsewhere.lua"
    vim.fn.writefile({ "" }, inside)
    vim.fn.writefile({ "" }, outside)

    require("fsbookmark.root").clear_cache()
    fsbookmark.setup({
      dir = tmpdir .. "/bookmarks",
      workspace = { enabled = true },
      watch = false,
      explorer = { enabled = false },
      keys = { enabled = false },
    })
    -- Resolution starts from the current buffer, so sit inside the project.
    vim.cmd.edit(inside)
    fsbookmark.load()
  end

  before_each(setup_workspace)
  after_each(function()
    vim.cmd("silent! %bwipeout!")
    require("fsbookmark.root").clear_cache()
  end)

  it("resolves the root from a .git marker", function()
    local root, name = fsbookmark.workspace()
    assert.equals(ws_root, root)
    assert.equals("proj", name)
  end)

  it("routes paths by whether they live under the root", function()
    assert.equals("workspace", fsbookmark.add(inside).scope)
    assert.equals("global", fsbookmark.add(outside).scope)
  end)

  it("writes each scope to its own file", function()
    fsbookmark.add(inside)
    fsbookmark.add(outside)
    fsbookmark.save()

    local ws_file = store.file("workspace")
    assert.is_not_nil(ws_file)
    local ws = vim.json.decode(table.concat(vim.fn.readfile(ws_file), "\n"))
    local global = vim.json.decode(table.concat(vim.fn.readfile(global_file()), "\n"))

    assert.equals(1, #ws.bookmarks)
    assert.equals(inside, ws.bookmarks[1].path)
    assert.equals(ws_root, ws.root)
    assert.equals("proj", ws.name)

    assert.equals(1, #global.bookmarks)
    assert.equals(outside, global.bookmarks[1].path)
  end)

  it("does not persist the derived scope field", function()
    fsbookmark.add(inside)
    fsbookmark.save()
    local ws = vim.json.decode(table.concat(vim.fn.readfile(store.file("workspace")), "\n"))
    assert.is_nil(ws.bookmarks[1].scope)
  end)

  it("merges both files into one list", function()
    fsbookmark.add(inside)
    fsbookmark.add(outside)
    fsbookmark.save()
    fsbookmark.load()

    assert.equals(2, #fsbookmark.list())
    assert.equals("workspace", fsbookmark.get(inside).scope)
    assert.equals("global", fsbookmark.get(outside).scope)
  end)

  it("filters by scope:", function()
    fsbookmark.add(inside)
    fsbookmark.add(outside)

    assert.equals(1, #fsbookmark.search("scope:workspace"))
    assert.equals(1, #fsbookmark.search("scope:global"))
    -- Several scopes are an OR, not an AND.
    assert.equals(2, #fsbookmark.search("scope:global scope:workspace"))
  end)

  it("hides another workspace's bookmarks", function()
    fsbookmark.add(inside)
    fsbookmark.add(outside)
    fsbookmark.save()

    -- Move to an unrelated project: global stays, the other workspace does not.
    local other = tmpdir .. "/other"
    vim.fn.mkdir(other .. "/.git", "p")
    vim.fn.writefile({ "" }, other .. "/x.lua")
    require("fsbookmark.root").clear_cache()
    vim.cmd.edit(other .. "/x.lua")

    local paths = vim.tbl_map(function(b)
      return b.path
    end, fsbookmark.list())
    assert.same({ outside }, paths)
  end)

  it("moves a bookmark between files when a rename crosses the root", function()
    fsbookmark.add(inside, { description = "moved" })
    local moved = tmpdir .. "/moved.lua"
    require("fsbookmark.watch").on_rename(inside, moved)

    assert.equals("global", fsbookmark.get(moved).scope)
    fsbookmark.save()

    local ws = vim.json.decode(table.concat(vim.fn.readfile(store.file("workspace")), "\n"))
    local global = vim.json.decode(table.concat(vim.fn.readfile(global_file()), "\n"))
    assert.equals(0, #ws.bookmarks)
    assert.equals(1, #global.bookmarks)
    assert.equals("moved", global.bookmarks[1].description)
  end)

  it("keeps everything global when workspaces are disabled", function()
    fsbookmark.setup({
      dir = tmpdir .. "/bookmarks2",
      workspace = { enabled = false },
      watch = false,
      explorer = { enabled = false },
      keys = { enabled = false },
    })
    assert.is_nil(fsbookmark.workspace())
    assert.equals("global", fsbookmark.add(inside).scope)
  end)

  it("migrates a pre-workspace bookmarks.json", function()
    local dir = tmpdir .. "/migrate"
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({
      vim.json.encode({ version = 1, bookmarks = { { path = outside, description = "legacy" } } }),
    }, dir .. "/bookmarks.json")

    fsbookmark.setup({
      dir = dir .. "/bookmarks",
      workspace = { enabled = false },
      watch = false,
      explorer = { enabled = false },
      keys = { enabled = false },
    })

    assert.equals("legacy", fsbookmark.get(outside).description)
    assert.equals(0, vim.fn.filereadable(dir .. "/bookmarks.json"))
    assert.equals(1, vim.fn.filereadable(dir .. "/bookmarks/global.json"))
  end)
end)

describe("events", function()
  before_each(reset)

  local function capture(pattern, fn)
    local seen = {}
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = pattern,
      callback = function(args)
        table.insert(seen, args.data)
      end,
    })
    fn()
    vim.api.nvim_del_autocmd(id)
    return seen
  end

  it("emits on add", function()
    local seen = capture("FSBookmarkAdd", function()
      fsbookmark.add(file_a)
    end)
    assert.equals(1, #seen)
    assert.equals(file_a, seen[1].path)
  end)

  it("emits on remove", function()
    fsbookmark.add(file_a)
    assert.equals(1, #capture("FSBookmarkRemove", function()
      fsbookmark.remove(file_a)
    end))
  end)

  it("emits on update", function()
    fsbookmark.add(file_a)
    assert.equals(1, #capture("FSBookmarkUpdate", function()
      fsbookmark.update(file_a, { description = "x" })
    end))
  end)
end)

describe("watch", function()
  before_each(reset)

  it("follows renames", function()
    fsbookmark.add(file_a, { description = "Runtime" })
    local moved = tmpdir .. "/runtime2.py"
    require("fsbookmark.watch").on_rename(file_a, moved)

    assert.is_nil(fsbookmark.get(file_a))
    assert.equals("Runtime", fsbookmark.get(moved).description)
  end)

  it("prunes broken bookmarks", function()
    fsbookmark.add(file_a)
    fsbookmark.add(file_b)
    vim.fn.delete(file_a)

    assert.equals(1, require("fsbookmark.watch").prune())
    assert.equals(1, #fsbookmark.list())
  end)
end)
