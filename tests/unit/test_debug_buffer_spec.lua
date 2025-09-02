local eq = assert.are.same

-- Stub debug module for isolation
package.loaded["lensline.debug"] = nil

describe("debug buffer system", function()
  local debug
  local test_cache_dir
  
  -- Helper to create temporary test directory
  local function setup_test_cache()
    test_cache_dir = vim.fn.tempname() .. "_lensline_test"
    vim.fn.mkdir(test_cache_dir, "p")
    return test_cache_dir
  end
  
  -- Helper to clean up test files
  local function cleanup_test_cache()
    if test_cache_dir and vim.fn.isdirectory(test_cache_dir) == 1 then
      vim.fn.delete(test_cache_dir, "rf")
    end
  end
  
  -- Helper to stub config and cache dir
  local function with_debug_test_setup(fn)
    local orig_stdpath = vim.fn.stdpath
    local orig_config = package.loaded["lensline.config"]
    
    -- Setup test environment
    setup_test_cache()
    
    vim.fn.stdpath = function(what)
      if what == "cache" then
        return test_cache_dir
      end
      return orig_stdpath(what)
    end
    
    package.loaded["lensline.config"] = {
      get = function() return { debug_mode = true } end
    }
    
    -- Clean module state
    package.loaded["lensline.debug"] = nil
    
    local ok, err = pcall(fn)
    
    -- Cleanup
    vim.fn.stdpath = orig_stdpath
    package.loaded["lensline.config"] = orig_config
    package.loaded["lensline.debug"] = nil
    cleanup_test_cache()
    
    if not ok then error(err) end
  end
  
  before_each(function()
    -- Ensure clean state
    package.loaded["lensline.debug"] = nil
  end)
  
  after_each(function()
    package.loaded["lensline.debug"] = nil
    cleanup_test_cache()
  end)
  
  describe("buffer management", function()
    it("initializes with empty buffer", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        local info = debug.get_session_info()
        eq(0, info.buffer_count)
        eq(100, info.buffer_limit)
      end)
    end)
    
    it("accumulates log entries in buffer", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        local info_before = debug.get_session_info()
        local initial_count = info_before.buffer_count
        
        debug.init() -- This adds header messages to buffer
        
        -- Add a few log entries
        debug.log("test message 1")
        debug.log("test message 2")
        debug.log("test message 3")
        
        local info = debug.get_session_info()
        -- Should have 3 test messages plus whatever header messages init() added
        eq(true, info.buffer_count >= 3)
        -- More precisely, check that we added exactly 3 messages since init
        local info_after_init = debug.get_session_info()
        debug.log("test message 1")
        debug.log("test message 2")
        debug.log("test message 3")
        local info_final = debug.get_session_info()
        eq(info_after_init.buffer_count + 3, info_final.buffer_count)
      end)
    end)
    
    it("does not write to file until buffer is full", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        local info_before = debug.get_session_info()
        
        debug.init() -- This adds header messages to buffer
        local info_after_init = debug.get_session_info()
        local header_count = info_after_init.buffer_count
        
        -- Add 50 entries (less than buffer limit)
        for i = 1, 50 do
          debug.log("test message " .. i)
        end
        
        local info = debug.get_session_info()
        eq(header_count + 50, info.buffer_count)
        
        -- File doesn't exist yet because nothing has been flushed (everything is buffered)
        eq(false, info.exists)
        
        -- After manual flush, file should exist and contain all messages
        debug.flush()
        local info_after_flush = debug.get_session_info()
        eq(true, info_after_flush.exists)
        eq(0, info_after_flush.buffer_count) -- Buffer should be empty after flush
        
        local file_content = vim.fn.readfile(info_after_flush.file_path)
        local test_messages_in_file = 0
        for _, line in ipairs(file_content) do
          if line:match("test message") then
            test_messages_in_file = test_messages_in_file + 1
          end
        end
        eq(50, test_messages_in_file) -- Should have all 50 test messages after flush
      end)
    end)
  end)
  
  describe("buffer flushing", function()
    it("flushes when buffer reaches limit", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        debug.init()
        
        -- Add exactly 100 entries to trigger flush
        for i = 1, 100 do
          debug.log("test message " .. i)
        end
        
        -- Allow scheduled flush to complete
        vim.wait(100, function() return false end)
        
        local info = debug.get_session_info()
        eq(0, info.buffer_count) -- Buffer should be empty after flush
        
        -- File should contain all messages
        local file_content = vim.fn.readfile(info.file_path)
        local test_messages = 0
        for _, line in ipairs(file_content) do
          if line:match("test message") then
            test_messages = test_messages + 1
          end
        end
        eq(100, test_messages)
      end)
    end)
    
    it("manual flush works correctly", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        debug.init()
        local info_after_init = debug.get_session_info()
        local header_count = info_after_init.buffer_count
        
        -- Add some entries (less than limit)
        for i = 1, 25 do
          debug.log("manual test " .. i)
        end
        
        local info_before = debug.get_session_info()
        eq(header_count + 25, info_before.buffer_count)
        
        -- Manual flush
        local success = debug.flush()
        eq(true, success)
        
        local info_after = debug.get_session_info()
        eq(0, info_after.buffer_count) -- Buffer should be empty
        
        -- Verify messages were written
        local file_content = vim.fn.readfile(info_after.file_path)
        local test_messages = 0
        for _, line in ipairs(file_content) do
          if line:match("manual test") then
            test_messages = test_messages + 1
          end
        end
        eq(25, test_messages)
      end)
    end)
    
    it("handles flush with empty buffer gracefully", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        debug.init()
        
        -- Flush empty buffer
        local success = debug.flush()
        eq(true, success)
        
        local info = debug.get_session_info()
        eq(0, info.buffer_count)
      end)
    end)
  end)
  
  describe("error handling", function()
    it("restores buffer on flush failure", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        debug.init()
        local info_after_init = debug.get_session_info()
        local header_count = info_after_init.buffer_count
        
        -- Add some entries
        for i = 1, 10 do
          debug.log("error test " .. i)
        end
        
        local info_before_flush = debug.get_session_info()
        local total_before_flush = info_before_flush.buffer_count
        
        -- Ensure we actually have buffered content
        eq(true, total_before_flush > 0, "Buffer should have content before flush")
        
        -- Simulate file write failure by temporarily overriding io.open
        local info = debug.get_session_info()
        local original_io_open = io.open
        
        -- Override io.open to fail for ANY file open operation during flush
        -- This ensures we catch the file operation regardless of path resolution
        local flush_started = false
        io.open = function(filename, mode)
          if flush_started then
            return nil  -- Simulate file open failure during flush
          end
          return original_io_open(filename, mode)
        end
        
        -- Mark that we're starting the flush operation
        flush_started = true
        
        -- Attempt flush (should fail and restore buffer)
        local success = debug.flush()
        eq(false, success)
        
        -- Buffer should be restored to the same count as before flush
        local info_after = debug.get_session_info()
        eq(total_before_flush, info_after.buffer_count)
        
        -- Cleanup: restore original io.open function
        io.open = original_io_open
      end)
    end)
  end)
  
  describe("exit handler", function()
    it("registers VimLeavePre autocommand", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        debug.init()
        
        -- Add a log entry (this should register the exit handler)
        debug.log("test message")
        
        -- Check that autocommand is registered
        local autocommands = vim.api.nvim_get_autocmds({
          event = "VimLeavePre",
          pattern = "*"
        })
        
        local found_handler = false
        for _, autocmd in ipairs(autocommands) do
          if autocmd.desc and autocmd.desc:match("lensline debug") then
            found_handler = true
            break
          end
        end
        eq(true, found_handler)
      end)
    end)
  end)
  
  describe("API compatibility", function()
    it("preserves log_context function", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        
        -- Clear any initial state by initializing fresh
        debug.init()
        local info_after_init = debug.get_session_info()
        local count_after_init = info_after_init.buffer_count
        
        -- Should not error
        debug.log_context("TestContext", "test message")
        
        local info_after = debug.get_session_info()
        eq(count_after_init + 1, info_after.buffer_count)
      end)
    end)
    
    it("preserves log_lsp_request function", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        
        -- Clear any initial state by initializing fresh
        debug.init()
        local info_after_init = debug.get_session_info()
        local count_after_init = info_after_init.buffer_count
        
        -- Should not error
        debug.log_lsp_request("textDocument/references", {}, "TestLSP")
        
        local info_after = debug.get_session_info()
        eq(count_after_init + 2, info_after.buffer_count) -- method + params = 2 log entries
      end)
    end)
    
    it("preserves log_lsp_response function", function()
      with_debug_test_setup(function()
        debug = require("lensline.debug")
        
        -- Clear any initial state by initializing fresh
        debug.init()
        local info_after_init = debug.get_session_info()
        local count_after_init = info_after_init.buffer_count
        
        -- Should not error
        debug.log_lsp_response("textDocument/references", {}, "TestLSP")
        
        local info_after = debug.get_session_info()
        eq(count_after_init + 2, info_after.buffer_count) -- method + results = 2 log entries
      end)
    end)
  end)
  
  describe("disabled mode", function()
    it("does nothing when debug_mode is false", function()
      local orig_config = package.loaded["lensline.config"]
      
      -- Use disabled config
      package.loaded["lensline.config"] = {
        get = function() return { debug_mode = false } end
      }
      package.loaded["lensline.debug"] = nil
      
      debug = require("lensline.debug")
      debug.log("should be ignored")
      
      local info = debug.get_session_info()
      eq(nil, info.id)
      eq(nil, info.file_path)
      eq(0, info.buffer_count)
      
      -- Cleanup
      package.loaded["lensline.config"] = orig_config
      package.loaded["lensline.debug"] = nil
    end)
  end)
end)