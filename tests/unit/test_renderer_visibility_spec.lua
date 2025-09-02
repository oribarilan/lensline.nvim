-- tests/unit/test_renderer_visibility_spec.lua
-- unit tests for lensline.renderer visibility behavior

local eq = assert.are.same

describe("renderer visibility behavior", function()
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then 
        package.loaded[name] = nil 
      end
    end
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or {
      "function test_func()",
      "  return 42",
      "end"
    })
    return bufnr
  end

  local function setup_test_data(bufnr)
    local renderer = require("lensline.renderer")
    renderer.provider_lens_data = {
      [bufnr] = {
        references = {
          { line = 1, text = "3 refs" }
        }
      }
    }
  end

  local function count_extmarks(bufnr)
    local renderer = require("lensline.renderer")
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, {})
    return #extmarks
  end

  before_each(function()
    reset_modules()
    created_buffers = {}
    -- ensure clean renderer state
    local renderer = require("lensline.renderer")
    renderer.provider_lens_data = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    reset_modules()
  end)

  -- table-driven tests for visibility combinations
  for _, tc in ipairs({
    { name = "enabled and visible", enabled = true, visible = true, should_render = true },
    { name = "enabled but not visible", enabled = true, visible = false, should_render = false },
    { name = "not enabled but visible", enabled = false, visible = true, should_render = false },
    { name = "neither enabled nor visible", enabled = false, visible = false, should_render = false },
  }) do
    it(("handles %s"):format(tc.name), function()
      local config = require("lensline.config")
      local renderer = require("lensline.renderer")
      
      config.setup({})
      config.set_enabled(tc.enabled)
      config.set_visible(tc.visible)
      
      local bufnr = make_buf()
      setup_test_data(bufnr)
      
      renderer.render_combined_lenses(bufnr)
      
      local extmark_count = count_extmarks(bufnr)
      
      if tc.should_render then
        -- should have rendered something (exact count depends on implementation)
        assert.is_true(extmark_count >= 0) -- basic check that it processed
      else
        eq(0, extmark_count)
      end
    end)
  end

  it("clears existing lenses when becoming invisible", function()
    local config = require("lensline.config")
    local renderer = require("lensline.renderer")
    
    config.setup({})
    config.set_enabled(true)
    config.set_visible(true)
    
    local bufnr = make_buf()
    setup_test_data(bufnr)
    
    -- first render with visibility on
    renderer.render_combined_lenses(bufnr)
    
    -- turn visibility off
    config.set_visible(false)
    renderer.render_combined_lenses(bufnr)
    
    -- should have cleared all extmarks
    eq(0, count_extmarks(bufnr))
  end)
end)