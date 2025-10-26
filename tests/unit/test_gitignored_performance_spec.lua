local eq = assert.are.same
local test_utils = require("tests.test_utils")

local await = test_utils.await

describe("gitignored files per-file checking", function()
  local original_system
  local original_finddir
  
  before_each(function()
    package.loaded["lensline.limits"] = nil
    package.loaded["lensline.config"] = nil
    original_system = vim.fn.system
    original_finddir = vim.fn.finddir
  end)
  
  after_each(function()
    vim.fn.system = original_system
    vim.fn.finddir = original_finddir
  end)
  
  describe("non-blocking behavior", function()
    it("should not block during initialization - no bulk caching", function()
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local check_ignore_calls = 0
      
      vim.fn.finddir = function(pattern, path)
        if pattern == '.git' then
          return '/test/project/.git'
        end
        return original_finddir(pattern, path)
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
          check_ignore_calls = check_ignore_calls + 1
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = true }
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/src/test_init_1.lua")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line 1", "line 2"})
      
      local start = vim.loop.hrtime()
      limits.should_skip(bufnr)
      local elapsed = (vim.loop.hrtime() - start) / 1e6
      
      assert.is_true(elapsed < 100, string.format("Check should not block (took %.2fms)", elapsed))
      assert.equals(1, check_ignore_calls, "Should use git check-ignore per file")
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
    
    it("should not call git ls-files during initialization", function()
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local ls_files_called = false
      
      vim.fn.finddir = function(pattern, path)
        if pattern == '.git' then
          return '/test/project/.git'
        end
        return original_finddir(pattern, path)
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[3] == "ls-files" then
          ls_files_called = true
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = true }
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/test_init_2.lua")
      
      limits.should_skip(bufnr)
      
      assert.is_false(ls_files_called, "Should not call git ls-files")
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
  
  describe("per-file checking", function()
    it("should use git check-ignore for individual files", function()
      package.loaded["lensline.limits"] = nil
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local check_ignore_calls = {}
      
      vim.fn.finddir = function(pattern, path)
        if pattern == '.git' then
          return '/test/project/.git'
        end
        return original_finddir(pattern, path)
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
          table.insert(check_ignore_calls, cmd[6])
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = true }
      
      local ignored_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(ignored_bufnr, "/test/project/node_modules/package_unique_1.js")
      vim.api.nvim_buf_set_lines(ignored_bufnr, 0, -1, false, {"line 1"})
      
      local not_ignored_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(not_ignored_bufnr, "/test/project/src/main_unique_1.lua")
      vim.api.nvim_buf_set_lines(not_ignored_bufnr, 0, -1, false, {"line 1"})
      
      limits.should_skip(ignored_bufnr)
      limits.should_skip(not_ignored_bufnr)
      
      assert.equals(2, #check_ignore_calls, "Should call git check-ignore twice")
      
      vim.api.nvim_buf_delete(ignored_bufnr, {force = true})
      vim.api.nvim_buf_delete(not_ignored_bufnr, {force = true})
    end)
    
    it("should cache check results to avoid repeated git calls", function()
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local check_ignore_call_count = 0
      
      vim.fn.finddir = function(pattern, path)
        if pattern == '.git' then
          return '/test/project/.git'
        end
        return original_finddir(pattern, path)
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
          check_ignore_call_count = check_ignore_call_count + 1
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = true }
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/test_cache_1.lua")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line 1"})
      
      limits.should_skip(bufnr)
      limits.should_skip(bufnr)
      limits.should_skip(bufnr)
      
      assert.equals(1, check_ignore_call_count, "Should cache result and only call git once")
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
  
  describe("memory efficiency", function()
    it("should only cache checked files not all ignored files", function()
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local check_calls = 0
      
      vim.fn.finddir = function(pattern, path)
        if pattern == '.git' then
          return '/test/project/.git'
        end
        return original_finddir(pattern, path)
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
          check_calls = check_calls + 1
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = true }
      
      local bufnr1 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr1, "/test/project/file_mem_1.lua")
      
      local bufnr2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr2, "/test/project/file_mem_2.lua")
      
      limits.should_skip(bufnr1)
      limits.should_skip(bufnr2)
      
      assert.equals(2, check_calls, "Should only check files that are accessed")
      
      vim.api.nvim_buf_delete(bufnr1, {force = true})
      vim.api.nvim_buf_delete(bufnr2, {force = true})
    end)
  end)
  
  describe("configuration", function()
    it("should respect exclude_gitignored = false and not call git", function()
      package.loaded["lensline.limits"] = nil
      package.loaded["lensline.config"] = nil
      
      local config = require("lensline.config")
      config.options.limits = { exclude_gitignored = false }
      
      local limits = require("lensline.limits")
      limits.clear_cache()
      
      local git_called = false
      
      vim.fn.system = function(cmd)
        if type(cmd) == "table" and cmd[1] == "git" then
          git_called = true
        end
        return ""
      end
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/node_modules/package_config_unique.js")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line 1"})
      
      local should_skip = limits.should_skip(bufnr)
      
      assert.is_false(git_called, "git should not be called when exclude_gitignored is false")
      assert.is_false(should_skip, "Should not skip when feature is disabled")
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
end)
