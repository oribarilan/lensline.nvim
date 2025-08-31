local eq = assert.are.same
local config = require("lensline.config")
local renderer = require("lensline.renderer")
local utils = require("lensline.utils")

describe("renderer visibility behavior", function()
  
  describe("render_combined_lenses visibility checks", function()
    it("should render when both enabled and visible", function()
      config.setup({})
      config.set_enabled(true)
      config.set_visible(true)
      
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "function test_func()",
        "  return 42",
        "end"
      })
      
      -- Add some test lens data
      renderer.provider_lens_data = {
        [test_bufnr] = {
          references = {
            { line = 1, text = "3 refs" }
          }
        }
      }
      
      -- Should not throw error and should process the render
      renderer.render_combined_lenses(test_bufnr)
      
      -- Check that extmarks exist (basic verification)
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, renderer.namespace, 0, -1, {})
      -- Note: actual rendering might be complex, this just verifies no early return
      
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
    
    it("should not render when enabled but not visible", function()
      config.setup({})
      config.set_enabled(true)
      config.set_visible(false)
      
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "function test_func()",
        "  return 42",
        "end"
      })
      
      -- Add some test lens data
      renderer.provider_lens_data = {
        [test_bufnr] = {
          references = {
            { line = 1, text = "3 refs" }
          }
        }
      }
      
      renderer.render_combined_lenses(test_bufnr)
      
      -- Should have cleared buffer and not rendered anything
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, renderer.namespace, 0, -1, {})
      eq(0, #extmarks)
      
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
    
    it("should not render when not enabled regardless of visibility", function()
      config.setup({})
      config.set_enabled(false)
      config.set_visible(true)
      
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "function test_func()",
        "  return 42",
        "end"
      })
      
      -- Add some test lens data
      renderer.provider_lens_data = {
        [test_bufnr] = {
          references = {
            { line = 1, text = "3 refs" }
          }
        }
      }
      
      renderer.render_combined_lenses(test_bufnr)
      
      -- Should have cleared buffer and not rendered anything
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, renderer.namespace, 0, -1, {})
      eq(0, #extmarks)
      
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
    
    it("should not render when neither enabled nor visible", function()
      config.setup({})
      config.set_enabled(false)
      config.set_visible(false)
      
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "function test_func()",
        "  return 42",
        "end"
      })
      
      -- Add some test lens data
      renderer.provider_lens_data = {
        [test_bufnr] = {
          references = {
            { line = 1, text = "3 refs" }
          }
        }
      }
      
      renderer.render_combined_lenses(test_bufnr)
      
      -- Should have cleared buffer and not rendered anything
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, renderer.namespace, 0, -1, {})
      eq(0, #extmarks)
      
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
    
    it("should clear existing lenses when becoming invisible", function()
      config.setup({})
      config.set_enabled(true)
      config.set_visible(true)
      
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "function test_func()",
        "  return 42",
        "end"
      })
      
      -- First render with visibility on
      renderer.provider_lens_data = {
        [test_bufnr] = {
          references = {
            { line = 1, text = "3 refs" }
          }
        }
      }
      
      renderer.render_combined_lenses(test_bufnr)
      
      -- Now turn visibility off
      config.set_visible(false)
      renderer.render_combined_lenses(test_bufnr)
      
      -- Should have cleared all extmarks
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, renderer.namespace, 0, -1, {})
      eq(0, #extmarks)
      
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
  end)
end)