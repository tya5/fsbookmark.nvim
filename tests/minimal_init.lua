-- Minimal init for `make test`. Only plenary is required.
local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h:h")
local deps = root .. "/.tests/site/pack/deps/start"

vim.opt.runtimepath:prepend(root)
for _, dir in ipairs(vim.fn.glob(deps .. "/*", true, true)) do
  vim.opt.runtimepath:append(dir)
end

vim.opt.swapfile = false
vim.env.XDG_DATA_HOME = root .. "/.tests/data"
