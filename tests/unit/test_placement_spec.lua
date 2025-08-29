local eq = assert.are.same

-- Minimal debug stub to avoid noise
package.loaded["lensline.debug"] = { log_context = function() end }

local config = require("lensline.config")
local renderer = require("lensline.renderer")

-- Helpers
local function new_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function collect_extmarks(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
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

local function reset_config(placement, providers)
  config.setup({
    providers = providers or {
      { name = "p1", enabled = true },
    },
    style = { 
      prefix = "", 
      separator = " • ", 
      highlight = "Comment", 
      placement = placement,
      use_nerdfont = false 
    },
  })
  renderer.provider_lens_data = {}
end

describe("placement configuration", function()
  before_each(function()
    renderer.provider_lens_data = {}
  end)

  it("renders above placement by default", function()
    reset_config("above")
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "test above" },
    })

    local by_line = collect_extmarks(buf)
    eq("test above", by_line[1].text)
    eq("above", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("renders inline placement when configured", function()
    reset_config("inline")
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "test inline" },
    })

    local by_line = collect_extmarks(buf)
    eq(" test inline", by_line[1].text)  -- Note the leading space for inline
    eq("inline", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("defaults to above placement when placement not specified", function()
    config.setup({
      providers = { { name = "p1", enabled = true } },
      style = { prefix = "", separator = " • ", highlight = "Comment", use_nerdfont = false },
    })
    renderer.provider_lens_data = {}
    
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "default test" },
    })

    local by_line = collect_extmarks(buf)
    eq("default test", by_line[1].text)
    eq("above", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("combines multiple providers correctly in inline mode", function()
    reset_config("inline", {
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "A" },
    })
    renderer.render_provider_lenses(buf, "p2", {
      { line = 1, text = "B" },
    })

    local by_line = collect_extmarks(buf)
    eq(" A • B", by_line[1].text)
    eq("inline", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("combines multiple providers correctly in above mode", function()
    reset_config("above", {
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "A" },
    })
    renderer.render_provider_lenses(buf, "p2", {
      { line = 1, text = "B" },
    })

    local by_line = collect_extmarks(buf)
    eq("A • B", by_line[1].text)
    eq("above", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles empty results in both placement modes", function()
    for _, placement in ipairs({"above", "inline"}) do
      reset_config(placement)
      local buf = new_buf({ "function test()", "  return 1", "end" })

      renderer.render_provider_lenses(buf, "p1", {})
      local _, marks = collect_extmarks(buf)
      eq(0, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("switches placement modes correctly when config changes", function()
    -- Start with above
    reset_config("above")
    local buf = new_buf({ "function test()", "  return 1", "end" })

    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "test" },
    })

    local by_line = collect_extmarks(buf)
    eq("above", by_line[1].placement)

    -- Switch to inline
    reset_config("inline")
    renderer.render_provider_lenses(buf, "p1", {
      { line = 1, text = "test" },
    })

    by_line = collect_extmarks(buf)
    eq("inline", by_line[1].placement)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("respects separator in both placement modes", function()
    for _, placement in ipairs({"above", "inline"}) do
      config.setup({
        providers = {
          { name = "p1", enabled = true },
          { name = "p2", enabled = true },
        },
        style = { 
          prefix = "", 
          separator = " | ", 
          highlight = "Comment", 
          placement = placement,
          use_nerdfont = false 
        },
      })
      renderer.provider_lens_data = {}
      
      local buf = new_buf({ "function test()", "  return 1", "end" })

      renderer.render_provider_lenses(buf, "p1", {
        { line = 1, text = "A" },
      })
      renderer.render_provider_lenses(buf, "p2", {
        { line = 1, text = "B" },
      })

      local by_line = collect_extmarks(buf)
      if placement == "inline" then
        eq(" A | B", by_line[1].text)
      else
        eq("A | B", by_line[1].text)
      end

      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("validates configuration and function existence", function()
    local config = require("lensline.config")
    local renderer = require("lensline.renderer")
    
    -- Test inline placement config
    config.setup({ style = { placement = "inline" } })
    local opts = config.get()
    eq("inline", opts.style.placement)
    
    -- Test render_inline_lenses function exists
    eq("function", type(renderer.render_inline_lenses))
    
    -- Test default fallback when placement not specified
    config.setup({ style = { separator = " | " } })
    opts = config.get()
    eq("above", opts.style.placement)
  end)
end)