local M = {}

--- Score `needle` as a subsequence of `haystack`. Higher is better.
--- Returns nil when there is no match at all.
---@param haystack string
---@param needle string
---@return number|nil
function M.fuzzy(haystack, needle)
  if needle == "" then
    return 0
  end
  haystack, needle = haystack:lower(), needle:lower()

  local exact = haystack:find(needle, 1, true)
  if exact then
    -- Contiguous matches beat scattered ones, and earlier beats later.
    return 1000 + #needle * 10 - exact
  end

  local score, pos, streak = 0, 0, 0
  for i = 1, #needle do
    local found = haystack:find(needle:sub(i, i), pos + 1, true)
    if not found then
      return nil
    end
    streak = (found == pos + 1) and streak + 1 or 0
    score = score + 1 + streak
    pos = found
  end
  return score
end

---@class FSBookmarkQuery
---@field terms string[]
---@field labels string[]
---@field scopes string[]

--- Split a raw query into free-text terms, `label:` and `scope:` filters.
---@param query string|nil
---@return FSBookmarkQuery
function M.parse(query)
  local parsed = { terms = {}, labels = {}, scopes = {} }
  for word in (query or ""):gmatch("%S+") do
    local label = word:match("^label:(.+)$")
    local scope = word:match("^scope:(.+)$")
    if label then
      table.insert(parsed.labels, label:lower())
    elseif scope then
      table.insert(parsed.scopes, scope:lower())
    else
      table.insert(parsed.terms, word)
    end
  end
  return parsed
end

---@param bookmark Bookmark
---@param term string
---@return number|nil
local function score_term(bookmark, term)
  local best = nil
  local function consider(score)
    if score and (not best or score > best) then
      best = score
    end
  end

  -- Scattered subsequence matching is only useful on short strings. Applied to
  -- a full absolute path it matches nearly everything, so the path is matched
  -- fuzzily on its basename and by substring on the rest.
  consider(M.fuzzy(vim.fn.fnamemodify(bookmark.path, ":t"), term))
  if bookmark.path:lower():find(term:lower(), 1, true) then
    consider(1000)
  end

  consider(M.fuzzy(bookmark.description or "", term))
  for _, label in ipairs(bookmark.labels or {}) do
    consider(M.fuzzy(label, term))
  end

  return best
end

---@param bookmark Bookmark
---@param label string
---@return boolean
local function has_label(bookmark, label)
  for _, item in ipairs(bookmark.labels or {}) do
    if item:lower() == label then
      return true
    end
  end
  return false
end

--- Match a single bookmark against a parsed query (AND across all terms).
---@param bookmark Bookmark
---@param parsed FSBookmarkQuery
---@return number|nil score
function M.match(bookmark, parsed)
  for _, label in ipairs(parsed.labels) do
    if not has_label(bookmark, label) then
      return nil
    end
  end

  -- Several `scope:` filters are an OR: `scope:global scope:workspace` is
  -- "either", not the empty set that ANDing them would give.
  if #parsed.scopes > 0 and not vim.tbl_contains(parsed.scopes, bookmark.scope or "global") then
    return nil
  end

  local total = 0
  for _, term in ipairs(parsed.terms) do
    local score = score_term(bookmark, term)
    if not score then
      return nil
    end
    total = total + score
  end
  return total
end

--- Filter and rank bookmarks by a raw query string.
---@param items Bookmark[]
---@param query string|nil
---@return Bookmark[]
function M.filter(items, query)
  local parsed = M.parse(query)
  if #parsed.terms == 0 and #parsed.labels == 0 and #parsed.scopes == 0 then
    return vim.deepcopy(items)
  end

  local scored = {}
  for index, bookmark in ipairs(items) do
    local score = M.match(bookmark, parsed)
    if score then
      table.insert(scored, { bookmark = bookmark, score = score, index = index })
    end
  end

  table.sort(scored, function(a, b)
    if a.score == b.score then
      return a.index < b.index
    end
    return a.score > b.score
  end)

  return vim.tbl_map(function(entry)
    return entry.bookmark
  end, scored)
end

return M
