local eq = assert.are.same

describe("limits / truncation", function()
  local limits = require("lensline.limits")
  local config = require("lensline.config")

  -- helper to (re)configure with specific max_lines
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
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  it("file below threshold: no truncation", function()
    setup_cfg(100)
    local bufnr = make_buf({ "a","b","c","d","e" })
    local skip, reason, meta = limits.should_skip(bufnr)
    eq(false, skip)
    eq(nil, reason)
    eq(5, meta.line_count)
    eq(nil, meta.truncate_to)
    eq(5, limits.get_truncated_end_line(bufnr, meta.line_count))
  end)

  it("file exactly at threshold: no truncation", function()
    setup_cfg(10)
    local lines = {}
    for i = 1,10 do lines[i] = ("line %d"):format(i) end
    local bufnr = make_buf(lines)
    local _, _, meta = limits.should_skip(bufnr)
    eq(10, meta.line_count)
    eq(nil, meta.truncate_to)
    eq(10, limits.get_truncated_end_line(bufnr, 10))
  end)

  it("file above threshold: truncated end line", function()
    setup_cfg(25)
    local lines = {}
    for i = 1,40 do lines[i] = ("L%d"):format(i) end
    local bufnr = make_buf(lines)
    local _, _, meta = limits.should_skip(bufnr)
    eq(40, meta.line_count)
    eq(25, meta.truncate_to)
    eq(25, limits.get_truncated_end_line(bufnr, 40))
  end)

  it("zero-line (empty) buffer safe handling", function()
    setup_cfg(50)
    local bufnr = make_buf({})
    local skip, reason, meta = limits.should_skip(bufnr)
    eq(false, skip)
    eq(nil, reason)
    -- Neovim empty new buffer reports 1 line (empty string)
    eq(1, meta.line_count)
    eq(nil, meta.truncate_to)
    eq(30, limits.get_truncated_end_line(bufnr, 30)) -- arbitrary requested end line preserved
  end)

  it("cache reuse does not recompute metadata until changedtick changes", function()
    setup_cfg(15)
    local lines = {}
    for i = 1,20 do lines[i] = ("x%d"):format(i) end
    local bufnr = make_buf(lines)
    local _, _, meta1 = limits.should_skip(bufnr)
    -- second call should hit cache; metadata identical
    local _, _, meta2 = limits.should_skip(bufnr)
    eq(meta1.truncate_to, meta2.truncate_to)
    eq(15, limits.get_truncated_end_line(bufnr, 100))
  end)
end)