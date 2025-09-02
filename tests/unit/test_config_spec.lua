-- tests/unit/test_config_spec.lua
-- unit tests for lensline.config (setup and merging logic)

local eq = assert.are.same

describe("config setup and merging", function()
  local config
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

  -- table-driven tests for style configuration
  for _, tc in ipairs({
    {
      name = "overrides nerdfont setting",
      input = { style = { use_nerdfont = false } },
      check = function(opts) return opts.style.use_nerdfont end,
      expected = false,
      unchanged = function(opts) return opts.style.highlight end,
      unchanged_expected = "Comment"
    },
    {
      name = "overrides prefix setting", 
      input = { style = { prefix = ">> " } },
      check = function(opts) return opts.style.prefix end,
      expected = ">> ",
      unchanged = function(opts) return opts.style.separator end,
      unchanged_expected = " • "
    },
  }) do
    it(("merges %s"):format(tc.name), function()
      config.setup(tc.input)
      local opts = config.get()
      
      eq(tc.expected, tc.check(opts))
      if tc.unchanged then
        eq(tc.unchanged_expected, tc.unchanged(opts))
      end
    end)
  end

  it("handles empty config", function()
    config.setup({})
    local opts = config.get()
    
    eq(true, opts.style.use_nerdfont)
    assert.is_true(#opts.providers >= 1)
  end)

  it("supports repeated setup calls", function()
    config.setup({ style = { prefix = "A" } })
    eq("A", config.get().style.prefix)
    
    config.setup({ style = { prefix = "B" } })
    local opts = config.get()
    eq("B", opts.style.prefix)
    eq(" • ", opts.style.separator) -- other defaults retained
  end)

  it("preserves provider structure", function()
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

describe("config provider integration", function()
  local config
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

  it("respects provider min_level config", function()
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
    eq(nil, result) -- simple function filtered out (S < L)
  end)
end)