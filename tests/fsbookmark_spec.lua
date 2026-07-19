local config = require("fsbookmark.config")
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
    file = tmpdir .. "/bookmarks.json",
    watch = false,
    explorer = { enabled = false },
    keys = { enabled = false },
  })
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
    }, config.file())

    fsbookmark.load()
    assert.equals(1, #fsbookmark.list())
    assert.equals("first", fsbookmark.get(file_a).description)
  end)

  it("writes a versioned envelope", function()
    fsbookmark.add(file_a)
    fsbookmark.save()
    local decoded = vim.json.decode(table.concat(vim.fn.readfile(config.file()), "\n"))
    assert.equals(store.SCHEMA_VERSION, decoded.version)
    assert.equals(1, #decoded.bookmarks)
  end)

  it("survives a corrupt file", function()
    vim.fn.writefile({ "{ not json" }, config.file())
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
