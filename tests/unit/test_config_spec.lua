-- tests/unit/test_config_spec.lua
-- unit tests for lensline.config (setup and merging logic)

local eq = assert.are.same

describe("config.setup and get", function()
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
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

  -- table-driven tests for style config scenarios
  for _, case in ipairs({
    {
      name = "overrides nerdfont setting",
      input = { style = { use_nerdfont = false } },
      check_field = "style.use_nerdfont",
      expected = false,
      unchanged_field = "style.highlight",
      unchanged_expected = "Comment"
    },
    {
      name = "overrides prefix setting",
      input = { style = { prefix = ">> " } },
      check_field = "style.prefix",
      expected = ">> ",
      unchanged_field = "style.separator",
      unchanged_expected = " • "
    },
  }) do
    it(("config setup %s"):format(case.name), function()
      config.setup(case.input)
      local opts = config.get()
      
      -- navigate to nested field (e.g., "style.use_nerdfont")
      local parts = vim.split(case.check_field, ".", { plain = true })
      local value = opts
      for _, part in ipairs(parts) do
        value = value[part]
      end
      eq(case.expected, value)
      
      -- verify unchanged field is preserved
      if case.unchanged_field then
        local unchanged_parts = vim.split(case.unchanged_field, ".", { plain = true })
        local unchanged_value = opts
        for _, part in ipairs(unchanged_parts) do
          unchanged_value = unchanged_value[part]
        end
        eq(case.unchanged_expected, unchanged_value)
      end
    end)
  end

  it("handles empty config defensively", function()
    config.setup({})
    local opts = config.get()
    
    eq(true, opts.style.use_nerdfont) -- default preserved
    assert.is_true(#opts.providers >= 1) -- providers list present
  end)

  it("supports idempotent repeated setup calls", function()
    config.setup({ style = { prefix = "A" } })
    eq("A", config.get().style.prefix)
    
    config.setup({ style = { prefix = "B" } })
    local opts = config.get()
    eq("B", opts.style.prefix)
    eq(" • ", opts.style.separator) -- other defaults retained
  end)

  it("preserves provider configuration structure", function()
    local provider_config = {
      providers = {
        { name = "complexity", enabled = true, min_level = "M" },
        { name = "references", enabled = false },
      }
    }
    
    config.setup(provider_config)
    local opts = config.get()
    
    eq(2, #opts.providers)
    eq("complexity", opts.providers[1].name)
    eq(true, opts.providers[1].enabled)
    eq("M", opts.providers[1].min_level)
    eq("references", opts.providers[2].name)
    eq(false, opts.providers[2].enabled)
  end)
end)

-- separate integration test for provider behavior
describe("config integration with providers", function()
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
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

  it("provider respects min_level configuration", function()
    config.setup({
      providers = {
        { name = "complexity", enabled = true, min_level = "L" },
      },
    })

    local complexity = require("lensline.providers.complexity")
    local buf = make_buf({
      "function foo()",
      "  return 1",
      "end",
    })

    local func_info = { line = 1, end_line = 3, name = "foo" }
    local provider_cfg = config.get().providers[1]
    local calls = 0
    local result = "unset"
    
    complexity.handler(buf, func_info, provider_cfg, function(res)
      calls = calls + 1
      result = res
    end)
    
    eq(1, calls)
    eq(nil, result) -- filtered out (simple function has S complexity, min_level is L)
  end)
end)