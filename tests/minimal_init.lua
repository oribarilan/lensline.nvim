-- tests/minimal_init.lua - minimal init for lensline tests (busted)
local root = vim.fn.getcwd()
vim.opt.runtimepath = vim.env.VIMRUNTIME .. "," .. root

-- Add local .rocks (Lua 5.1) paths if present (fallback install in Makefile)
local rocks = root .. "/.rocks"
if vim.fn.isdirectory(rocks) == 1 then
  local lua_path = rocks .. "/share/lua/5.1/?.lua;" .. rocks .. "/share/lua/5.1/?/init.lua;"
  local lua_cpath = rocks .. "/lib/lua/5.1/?.so;"
  if not package.path:find(rocks, 1, true) then
    package.path = lua_path .. package.path
  end
  if not package.cpath:find(rocks, 1, true) then
    package.cpath = lua_cpath .. package.cpath
  end
end

-- Disable a few built-ins that can interfere
vim.g.loaded_matchparen = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Load LuaRocks loader (for global installs)
pcall(require, 'luarocks.loader')

local ok = pcall(require, 'busted')
if not ok then
  error("[lensline tests] 'busted' not found (install with: luarocks install --lua-version=5.1 busted, or just run `make test`)")
end

_G.__lensline_test = { root = root }