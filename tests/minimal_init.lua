-- tests/minimal_init.lua - minimal init for lensline tests (pure busted, local .rocks tree)
local root = vim.fn.getcwd()
-- Force project root as working directory (defensive for some CI/shell invocations)
pcall(vim.cmd, "cd " .. root)
vim.opt.runtimepath = vim.env.VIMRUNTIME .. "," .. root

-- Ensure plugin source (lua/) is on package.path (runtimepath change after startup does not retroactively adjust it)
if not package.path:find(root .. "/lua/?.lua", 1, true) then
  package.path = table.concat({
    root .. "/lua/?.lua",
    root .. "/lua/?/init.lua",
  }, ";") .. ";" .. package.path
end

-- Inject local .rocks LuaRocks tree (installed via: make test-setup)
local rocks = root .. "/.rocks"
if vim.fn.isdirectory(rocks) == 1 then
  local lua_path = table.concat({
    rocks .. "/share/lua/5.1/?.lua",
    rocks .. "/share/lua/5.1/?/init.lua",
  }, ";") .. ";"
  local lua_cpath = rocks .. "/lib/lua/5.1/?.so;"
  if not package.path:find(rocks, 1, true) then
    package.path = lua_path .. package.path
  end
  if not package.cpath:find(rocks, 1, true) then
    package.cpath = lua_cpath .. package.cpath
  end
end

-- Expose luassert early so specs that execute before busted.runner can use assert.are / etc.
do
  local ok, lua_assert = pcall(require, "luassert")
  if ok and type(lua_assert) == "table" and lua_assert.are then
    _G.assert = lua_assert
  end
end

-- Disable built-in plugins we don't need
vim.g.loaded_matchparen = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- (busted loaded later by runner; we avoid requiring it here to not interfere with discovery)
_G.__lensline_test = { root = root }