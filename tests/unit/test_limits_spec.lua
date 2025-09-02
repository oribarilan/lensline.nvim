-- tests/unit/test_limits_spec.lua
-- unit tests for lensline.limits (truncation logic)

local eq = assert.are.same

describe("limits.should_skip and get_truncated_end_line", function()
  local limits = require("lensline.limits")
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    limits = require("lensline.limits")
    config = require("lensline.config")
  end

  local function setup_cfg(max_lines)
    config.setup({
      limits = {
        max_lines = max_lines,
        exclude = {},
        exclude_gitignored = false,
        max_lenses = 9999,
      },
      providers = {}, -- minimize unrelated processing
      debug_mode = false,
    })
    limits.clear_cache()
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  before_each(function()
    reset_modules()
    created_buffers = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    reset_modules()
  end)

  -- table-driven tests for threshold scenarios
  for _, case in ipairs({
    { name = "below threshold", max_lines = 100, line_count = 5, should_truncate = false },
    { name = "at threshold", max_lines = 10, line_count = 10, should_truncate = false },
    { name = "above threshold", max_lines = 25, line_count = 40, should_truncate = true },
  }) do
    it(("handles files %s (%d lines, max %d)"):format(case.name, case.line_count, case.max_lines), function()
      setup_cfg(case.max_lines)
      local lines = {}
      for i = 1, case.line_count do
        lines[i] = ("line %d"):format(i)
      end
      local bufnr = make_buf(lines)
      
      local skip, reason, meta = limits.should_skip(bufnr)
      
      eq(false, skip)
      eq(nil, reason)
      eq(case.line_count, meta.line_count)
      
      if case.should_truncate then
        eq(case.max_lines, meta.truncate_to)
        eq(case.max_lines, limits.get_truncated_end_line(bufnr, case.line_count))
      else
        eq(nil, meta.truncate_to)
        eq(case.line_count, limits.get_truncated_end_line(bufnr, case.line_count))
      end
    end)
  end

  it("handles empty buffer safely", function()
    setup_cfg(50)
    local bufnr = make_buf({})
    
    local skip, reason, meta = limits.should_skip(bufnr)
    
    eq(false, skip)
    eq(nil, reason)
    -- neovim empty buffer reports 1 line (empty string)
    eq(1, meta.line_count)
    eq(nil, meta.truncate_to)
    eq(30, limits.get_truncated_end_line(bufnr, 30)) -- arbitrary requested end line preserved
  end)

  it("reuses cache until buffer changes", function()
    setup_cfg(15)
    local lines = {}
    for i = 1, 20 do
      lines[i] = ("x%d"):format(i)
    end
    local bufnr = make_buf(lines)
    
    local _, _, meta1 = limits.should_skip(bufnr)
    local _, _, meta2 = limits.should_skip(bufnr)
    
    eq(meta1.truncate_to, meta2.truncate_to)
    eq(15, limits.get_truncated_end_line(bufnr, 100))
  end)
end)