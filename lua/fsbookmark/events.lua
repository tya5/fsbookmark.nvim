local M = {}

M.ADD = "FSBookmarkAdd"
M.REMOVE = "FSBookmarkRemove"
M.UPDATE = "FSBookmarkUpdate"

--- Fire `User <pattern>` with the bookmark attached as `data`.
---@param pattern string
---@param bookmark Bookmark|nil
function M.emit(pattern, bookmark)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    modeline = false,
    data = bookmark and vim.deepcopy(bookmark) or nil,
  })
end

return M
