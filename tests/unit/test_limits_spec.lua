-- tests/unit/test_limits_spec.lua
-- unit tests for lensline.limits (truncation + sync gate behaviour)

local eq = assert.are.same

describe("limits.get_truncated_end_line and should_skip_async", function()
  local limits, config
  local created_buffers = {}

  local function reset_modules()
    for name, _ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    limits = require("lensline.limits")
    config = require("lensline.config")
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  local function setup_limits(max_lines)
    config.setup({
      limits = {
        max_lines = max_lines,
        exclude = {},
        exclude_gitignored = false,
        max_lenses = 9999,
        max_lines_hidden = false,
      },
      providers = {},
    })
    limits.clear_cache()
  end

  local function sync_should_skip(bufnr)
    local skip, reason
    limits.should_skip_async(bufnr, function(s, r)
      skip, reason = s, r
    end)
    return skip, reason
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

  -- table-driven tests for file size scenarios
  for _, tc in ipairs({
    { name = "small file", max_lines = 100, line_count = 5, should_truncate = false },
    { name = "at threshold", max_lines = 10, line_count = 10, should_truncate = false },
    { name = "large file", max_lines = 25, line_count = 40, should_truncate = true },
  }) do
    it(("handles %s (%d lines, max %d)"):format(tc.name, tc.line_count, tc.max_lines), function()
      setup_limits(tc.max_lines)

      local lines = {}
      for i = 1, tc.line_count do
        lines[i] = ("line %d"):format(i)
      end
      local bufnr = make_buf(lines)

      local skip, reason = sync_should_skip(bufnr)
      eq(false, skip)
      eq(nil, reason)

      if tc.should_truncate then
        eq(tc.max_lines, limits.get_truncated_end_line(bufnr, tc.line_count))
      else
        eq(tc.line_count, limits.get_truncated_end_line(bufnr, tc.line_count))
      end
    end)
  end

  it("handles empty buffer", function()
    setup_limits(50)
    local bufnr = make_buf({})

    local skip, reason = sync_should_skip(bufnr)
    eq(false, skip)
    eq(nil, reason)
    eq(30, limits.get_truncated_end_line(bufnr, 30))
  end)

  it("get_truncated_end_line returns the same value on repeated calls", function()
    setup_limits(15)
    local lines = {}
    for i = 1, 20 do
      lines[i] = ("line%d"):format(i)
    end
    local bufnr = make_buf(lines)

    eq(15, limits.get_truncated_end_line(bufnr, 100))
    eq(15, limits.get_truncated_end_line(bufnr, 100))
  end)
end)
