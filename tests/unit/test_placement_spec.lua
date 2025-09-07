local eq = assert.are.same

-- Test state tracking
local created_buffers = {}

-- Module state reset function
local function reset_modules()
  package.loaded["lensline.config"] = nil
  package.loaded["lensline.renderer"] = nil
  package.loaded["lensline.debug"] = nil
end

-- Centralized buffer helper
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  table.insert(created_buffers, bufnr)
  if lines and #lines > 0 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

-- Helper to collect extmarks with placement information
local function collect_extmarks(bufnr, renderer_namespace)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer_namespace, 0, -1, { details = true })
  local by_line = {}
  
  for _, m in ipairs(marks) do
    local lnum = m[2] + 1
    local details = m[4]
    local text = nil
    local placement_type = nil
    
    -- Check for virt_lines (above placement)
    if details and details.virt_lines and details.virt_lines[1] then
      placement_type = "above"
      text = table.concat(vim.tbl_map(function(t) return t[1] end, details.virt_lines[1]), "")
    end
    
    -- Check for virt_text (inline placement)
    if details and details.virt_text then
      placement_type = "inline"
      text = table.concat(vim.tbl_map(function(t) return t[1] end, details.virt_text), "")
    end
    
    by_line[lnum] = { text = text, placement = placement_type }
  end
  
  return by_line, marks
end

-- Helper to setup config and reset renderer state
local function setup_config_and_renderer(placement, providers, prefix)
  local config = require("lensline.config")
  local renderer = require("lensline.renderer")
  
  config.setup({
    providers = providers or {
      { name = "p1", enabled = true },
    },
    style = {
      prefix = prefix or "",
      separator = " • ",
      highlight = "Comment",
      placement = placement,
      use_nerdfont = false
    },
  })
  
  renderer.provider_lens_data = {}
  return config, renderer
end

describe("placement configuration", function()
  before_each(function()
    reset_modules()
    created_buffers = {}
    
    -- Set up silent debug module
    package.loaded["lensline.debug"] = { 
      log_context = function() end -- Silent for tests
    }
  end)
  
  after_each(function()
    -- Clean up created buffers
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    created_buffers = {}
    
    reset_modules()
  end)
  
  describe("basic placement modes", function()
    local placement_test_cases = {
      {
        name = "should render above placement by default",
        placement = "above",
        expected_text = "test above",
        expected_placement = "above"
      },
      {
        name = "should render inline placement when configured",
        placement = "inline", 
        expected_text = " test inline", -- Note the leading space for inline
        expected_placement = "inline"
      }
    }
    
    for _, case in ipairs(placement_test_cases) do
      it(case.name, function()
        local config, renderer = setup_config_and_renderer(case.placement)
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        local test_text = case.placement == "inline" and "test inline" or "test above"
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = test_text },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        eq(case.expected_text, by_line[1].text)
        eq(case.expected_placement, by_line[1].placement)
      end)
    end
    
    it("should default to above placement when placement not specified", function()
      local config = require("lensline.config")
      local renderer = require("lensline.renderer")
      
      config.setup({
        providers = { { name = "p1", enabled = true } },
        style = { prefix = "", separator = " • ", highlight = "Comment", use_nerdfont = false },
      })
      renderer.provider_lens_data = {}
      
      local buf = make_buf({ "function test()", "  return 1", "end" })
      
      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "default test" },
      })
      
      local by_line = collect_extmarks(buf, renderer.namespace)
      eq("default test", by_line[1].text)
      eq("above", by_line[1].placement)
    end)
  end)
  
  describe("multiple providers", function()
    local multi_provider_test_cases = {
      {
        name = "should combine multiple providers correctly in inline mode",
        placement = "inline",
        expected_text = " A • B",
        expected_placement = "inline"
      },
      {
        name = "should combine multiple providers correctly in above mode",
        placement = "above",
        expected_text = "A • B",
        expected_placement = "above"
      }
    }
    
    for _, case in ipairs(multi_provider_test_cases) do
      it(case.name, function()
        local config, renderer = setup_config_and_renderer(case.placement, {
          { name = "p1", enabled = true },
          { name = "p2", enabled = true },
        })
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = "A" },
        })
        renderer.render_provider_lenses(buf, "p2", {
          { line = 1, text = "B" },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        eq(case.expected_text, by_line[1].text)
        eq(case.expected_placement, by_line[1].placement)
      end)
    end
  end)
  
  describe("edge cases", function()
    it("should handle empty results in both placement modes", function()
      local placement_modes = {"above", "inline"}
      
      for _, placement in ipairs(placement_modes) do
        local config, renderer = setup_config_and_renderer(placement)
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        renderer.render_provider_lenses(buf, "p1", {})
        local _, marks = collect_extmarks(buf, renderer.namespace)
        eq(0, #marks)
      end
    end)
    
    it("should switch placement modes correctly when config changes", function()
      local config, renderer = setup_config_and_renderer("above")
      local buf = make_buf({ "function test()", "  return 1", "end" })
      
      -- Start with above
      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "test" },
      })
      
      local by_line = collect_extmarks(buf, renderer.namespace)
      eq("above", by_line[1].placement)
      
      -- Switch to inline
      config, renderer = setup_config_and_renderer("inline")
      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "test" },
      })
      
      by_line = collect_extmarks(buf, renderer.namespace)
      eq("inline", by_line[1].placement)
    end)
  end)
  
  describe("separator configuration", function()
    it("should respect separator in both placement modes", function()
      local separator_test_cases = {
        {
          placement = "above",
          expected_text = "A | B"
        },
        {
          placement = "inline", 
          expected_text = " A | B"
        }
      }
      
      for _, case in ipairs(separator_test_cases) do
        local config = require("lensline.config")
        local renderer = require("lensline.renderer")
        
        config.setup({
          providers = {
            { name = "p1", enabled = true },
            { name = "p2", enabled = true },
          },
          style = { 
            prefix = "", 
            separator = " | ", 
            highlight = "Comment", 
            placement = case.placement,
            use_nerdfont = false 
          },
        })
        renderer.provider_lens_data = {}
        
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = "A" },
        })
        renderer.render_provider_lenses(buf, "p2", {
          { line = 1, text = "B" },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        eq(case.expected_text, by_line[1].text)
      end
    end)
  end)
  
  describe("multi-line function signatures", function()
    local multiline_test_cases = {
      {
        name = "should render inline placement on first line of multi-line function signature",
        placement = "inline",
        expected_text = " 3 refs",
        expected_placement = "inline"
      },
      {
        name = "should render above placement correctly for multi-line function signature",
        placement = "above",
        expected_text = "3 refs",
        expected_placement = "above"
      }
    }
    
    for _, case in ipairs(multiline_test_cases) do
      it(case.name, function()
        local config, renderer = setup_config_and_renderer(case.placement)
        local buf = make_buf({
          "function multiline_func(",
          "  param1,",
          "  param2,",
          "  param3",
          ")",
          "  return param1 + param2 + param3",
          "end"
        })
        
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = "3 refs" },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        
        -- Should render on line 1 (first line of function signature)
        eq(case.expected_text, by_line[1].text)
        eq(case.expected_placement, by_line[1].placement)
        
        -- Should not render on other lines
        for line = 2, 5 do
          eq(nil, by_line[line])
        end
      end)
    end
  end)
  
  describe("prefix configuration", function()
    local prefix_test_cases = {
      {
        name = "should respect prefix configuration in inline mode",
        placement = "inline",
        prefix = "┃ ",
        expected_text = " ┃ test inline"
      },
      {
        name = "should respect prefix configuration in above mode",
        placement = "above", 
        prefix = "┃ ",
        expected_text = "┃ test above"
      },
      {
        name = "should allow empty prefix override in inline mode",
        placement = "inline",
        prefix = "",
        expected_text = " test inline"
      },
      {
        name = "should allow empty prefix override in above mode",
        placement = "above",
        prefix = "",
        expected_text = "test above"
      }
    }
    
    for _, case in ipairs(prefix_test_cases) do
      it(case.name, function()
        local config, renderer = setup_config_and_renderer(case.placement, nil, case.prefix)
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        local test_text = case.placement == "inline" and "test inline" or "test above"
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = test_text },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        eq(case.expected_text, by_line[1].text)
        eq(case.placement, by_line[1].placement)
      end)
    end
    
    it("should combine providers with prefix in both modes", function()
      local combined_prefix_test_cases = {
        {
          placement = "inline",
          expected_text = " >>> A • B"
        },
        {
          placement = "above",
          expected_text = ">>> A • B"
        }
      }
      
      for _, case in ipairs(combined_prefix_test_cases) do
        local config, renderer = setup_config_and_renderer(case.placement, {
          { name = "p1", enabled = true },
          { name = "p2", enabled = true },
        }, ">>> ")
        local buf = make_buf({ "function test()", "  return 1", "end" })
        
        renderer.render_provider_lenses(buf, "p1", {
          { line = 1, text = "A" },
        })
        renderer.render_provider_lenses(buf, "p2", {
          { line = 1, text = "B" },
        })
        
        local by_line = collect_extmarks(buf, renderer.namespace)
        eq(case.expected_text, by_line[1].text)
        eq(case.placement, by_line[1].placement)
      end
    end)
  end)
  
  describe("configuration validation", function()
    it("should validate configuration and unified rendering", function()
      local config = require("lensline.config")
      local renderer = require("lensline.renderer")
      
      -- Test inline placement config
      config.setup({ style = { placement = "inline" } })
      local opts = config.get()
      eq("inline", opts.style.placement)
      
      -- Test render_combined_lenses function exists (unified rendering)
      eq("function", type(renderer.render_combined_lenses))
      
      -- Test default fallback when placement not specified
      config.setup({ style = { separator = " | " } })
      opts = config.get()
      eq("above", opts.style.placement)
    end)
  end)
  
  describe("extmark property validation", function()
    it("should create correct extmark properties for inline placement", function()
      local config, renderer = setup_config_and_renderer("inline")
      local buf = make_buf({ "function test()", "  return 1", "end" })
      
      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "5 refs" },
      })
      
      -- Get the actual extmark details
      local marks = vim.api.nvim_buf_get_extmarks(buf, renderer.namespace, 0, -1, { details = true })
      eq(1, #marks, "should have exactly one extmark")
      
      local mark = marks[1]
      local line = mark[2]
      local col = mark[3]
      local details = mark[4]
      
      -- Verify extmark positioning
      eq(0, line, "extmark should be on line 0 (0-based)")
      eq(0, col, "extmark column should be 0 for inline placement with virt_text_pos='eol'")
      
      -- Verify inline-specific properties
      eq(true, details.virt_text ~= nil, "should have virt_text property for inline placement")
      eq(nil, details.virt_lines, "should not have virt_lines property for inline placement")
      eq("eol", details.virt_text_pos, "should have virt_text_pos='eol' for inline placement")
      
      -- Verify text content
      local virt_text = details.virt_text
      eq(1, #virt_text, "should have exactly one virt_text entry")
      eq(" 5 refs", virt_text[1][1], "should have correct text with leading space")
    end)
    
    it("should create correct extmark properties for above placement", function()
      local config, renderer = setup_config_and_renderer("above")
      local buf = make_buf({ "function test()", "  return 1", "end" })
      
      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "5 refs" },
      })
      
      -- Get the actual extmark details
      local marks = vim.api.nvim_buf_get_extmarks(buf, renderer.namespace, 0, -1, { details = true })
      eq(1, #marks, "should have exactly one extmark")
      
      local mark = marks[1]
      local line = mark[2]
      local col = mark[3]
      local details = mark[4]
      
      -- Verify extmark positioning
      eq(0, line, "extmark should be on line 0 (0-based)")
      eq(0, col, "extmark column should be 0 for above placement")
      
      -- Verify above-specific properties
      eq(nil, details.virt_text, "should not have virt_text property for above placement")
      eq(true, details.virt_lines ~= nil, "should have virt_lines property for above placement")
      eq(true, details.virt_lines_above, "should have virt_lines_above=true for above placement")
      eq(nil, details.virt_text_pos, "should not have virt_text_pos for above placement")
      
      -- Verify text content
      local virt_lines = details.virt_lines
      eq(1, #virt_lines, "should have exactly one virt_line")
      eq("5 refs", virt_lines[1][1][1], "should have correct text without leading space")
    end)
  end)
end)