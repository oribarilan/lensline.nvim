local eq = assert.are.same
local limits = require("lensline.limits")
local test_utils = require("tests.test_utils")

local await = test_utils.await

describe("gitignored files caching performance", function()
  local original_system
  local original_spawn
  
  before_each(function()
    package.loaded["lensline.limits"] = nil
    limits = require("lensline.limits")
    original_system = vim.fn.system
    if vim.loop then
      original_spawn = vim.loop.spawn
    end
  end)
  
  after_each(function()
    vim.fn.system = original_system
    if vim.loop and original_spawn then
      vim.loop.spawn = original_spawn
    end
  end)
  
  describe("blocking behavior", function()
    it("should not block UI when caching large number of gitignored files", function()
      local large_output = {}
      for i = 1, 250000 do
        table.insert(large_output, "node_modules/package" .. i .. "/file.js")
      end
      local mock_output = table.concat(large_output, "\n")
      
      local system_called = false
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          system_called = true
          return mock_output
        end
        return ""
      end
      
      local start_time = vim.loop.hrtime()
      limits.cache_gitignored_files()
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
      
      assert.is_true(system_called, "git command should be called")
      assert.is_true(elapsed < 100, string.format("Caching should complete quickly (took %.2fms), but was blocking", elapsed))
    end)
    
    it("should not block during plugin initialization with large gitignored cache", function()
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          local files = {}
          for i = 1, 50000 do
            table.insert(files, "ignored/file" .. i .. ".js")
          end
          return table.concat(files, "\n")
        end
        return ""
      end
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line 1", "line 2"})
      
      local start = vim.loop.hrtime()
      
      limits.refresh_gitignored_cache()
      
      local result = limits.should_ignore(bufnr)
      
      local setup_time = (vim.loop.hrtime() - start) / 1e6
      
      assert.is_true(setup_time < 100, string.format("Limits check should not block (took %.2fms)", setup_time))
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
  
  describe("async behavior", function()
    it("should cache gitignored files asynchronously", function()
      local cache_started = false
      local cache_completed = false
      
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          cache_started = true
          vim.defer_fn(function()
            cache_completed = true
          end, 50)
          return "node_modules/\n.git/\nbuild/"
        end
        return ""
      end
      
      limits.cache_gitignored_files()
      
      assert.is_true(cache_started, "Cache should have started")
      assert.is_false(cache_completed, "Cache should not complete immediately (should be async)")
      
      await(function() return cache_completed end, 200)
      
      assert.is_true(cache_completed, "Cache should complete asynchronously")
    end)
    
    it("should handle file checks gracefully before cache is ready", function()
      local cache_ready = false
      
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          vim.defer_fn(function()
            cache_ready = true
          end, 100)
          return "node_modules/file.js"
        end
        return ""
      end
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")
      
      limits.cache_gitignored_files()
      
      local ignored_before = limits.should_ignore(bufnr)
      assert.is_false(ignored_before, "Should not block or error before cache ready")
      
      await(function() return cache_ready end, 200)
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
  
  describe("correctness with large file lists", function()
    it("should correctly cache and lookup files from large gitignored list", function()
      local files = {}
      for i = 1, 10000 do
        table.insert(files, "node_modules/pkg" .. i .. "/index.js")
      end
      table.insert(files, "node_modules/special/target.js")
      
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          return table.concat(files, "\n")
        end
        return ""
      end
      
      limits.cache_gitignored_files()
      
      await(function()
        return limits.gitignored_files and #limits.gitignored_files > 0
      end, 500)
      
      local ignored_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(ignored_bufnr, "/test/project/node_modules/special/target.js")
      
      local not_ignored_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(not_ignored_bufnr, "/test/project/src/main.lua")
      
      local should_ignore_1 = limits.should_ignore(ignored_bufnr)
      local should_ignore_2 = limits.should_ignore(not_ignored_bufnr)
      
      assert.is_true(should_ignore_1, "Should correctly identify gitignored file from large list")
      assert.is_false(should_ignore_2, "Should correctly identify non-gitignored file")
      
      vim.api.nvim_buf_delete(ignored_bufnr, {force = true})
      vim.api.nvim_buf_delete(not_ignored_bufnr, {force = true})
    end)
    
    it("should handle extremely large gitignored lists without excessive memory", function()
      local huge_list = {}
      for i = 1, 100000 do
        table.insert(huge_list, string.format("node_modules/pkg%d/file.js", i))
      end
      
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          return table.concat(huge_list, "\n")
        end
        return ""
      end
      
      collectgarbage("collect")
      local mem_before = collectgarbage("count")
      
      limits.cache_gitignored_files()
      
      await(function()
        return limits.gitignored_files and #limits.gitignored_files > 0
      end, 1000)
      
      collectgarbage("collect")
      local mem_after = collectgarbage("count")
      local mem_used_kb = mem_after - mem_before
      
      assert.is_true(mem_used_kb < 50000, string.format("Memory usage should be reasonable (used %.2f KB)", mem_used_kb))
    end)
  end)
  
  describe("configuration", function()
    it("should respect exclude_gitignored = false and not block", function()
      local git_called = false
      vim.fn.system = function(cmd)
        if type(cmd) == "string" and cmd:match("git ls%-files.*ignored") then
          git_called = true
          local files = {}
          for i = 1, 50000 do
            table.insert(files, "node_modules/file" .. i)
          end
          return table.concat(files, "\n")
        end
        return ""
      end
      
      local config = require("lensline.config")
      config.limits.exclude_gitignored = false
      
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/project/node_modules/package.js")
      
      local start = vim.loop.hrtime()
      local ignored = limits.should_ignore(bufnr)
      local elapsed = (vim.loop.hrtime() - start) / 1e6
      
      assert.is_false(git_called, "git should not be called when exclude_gitignored is false")
      assert.is_false(ignored, "Should not ignore when feature is disabled")
      assert.is_true(elapsed < 10, "Should be instant when feature disabled")
      
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)
end)
