-- tests/unit/providers/test_usages_spec.lua
-- unit tests for lensline.providers.usages

local eq = assert.are.same

describe("lensline.providers.usages", function()
  local usages_provider = require("lensline.providers.usages")
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    usages_provider = require("lensline.providers.usages")
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

  it("has correct provider metadata", function()
    eq("usages", usages_provider.name)
    eq({ "LspAttach", "BufWritePost" }, usages_provider.event)
    eq("function", type(usages_provider.handler))
  end)

  -- table-driven tests for different configuration scenarios
  for _, case in ipairs({
    {
      name = "single attribute (nerdfont enabled)",
      provider_config = {
        include = { "refs" },
        breakdown = false,
        labels = { refs = "refs", usages = "usages" },
        icon_for_single = "",
        inner_separator = ", ",
      },
      expected = "󰌹 5"  -- nerdfont enabled by default, shows icon only
    },
    {
      name = "multiple attributes (nerdfont enabled)",
      provider_config = {
        include = { "refs", "defs", "impls" },
        breakdown = false,
        labels = { refs = "refs", defs = "defs", impls = "impls", usages = "usages" },
        icon_for_single = "",
        inner_separator = ", ",
      },
      expected = "󰌹 8"  -- nerdfont enabled by default, shows icon only
    },
    {
      name = "partial include subset (nerdfont enabled)",
      provider_config = {
        include = { "refs", "defs" },
        breakdown = false,
        labels = { refs = "refs", defs = "defs", impls = "impls", usages = "usages" },
        icon_for_single = nil,
        inner_separator = ", ",
      },
      expected = "󰌹 6"  -- nerdfont enabled by default, shows icon only
    },
    {
      name = "breakdown mode",
      provider_config = {
        include = { "refs", "defs", "impls" },
        breakdown = true,
        labels = { refs = "refs", defs = "defs", impls = "impls", usages = "usages" },
        icon_for_single = "",
        inner_separator = ", ",
      },
      expected = "5 refs, 1 defs, 2 impls"
    },
  }) do
    it(("displays correct text for %s"):format(case.name), function()
      local bufnr = make_buf({"function test() end"})
      local func_info = { line = 1, name = "test" }
      
      local result = nil
      usages_provider.handler(bufnr, func_info, case.provider_config, function(res)
        result = res
      end)
      
      eq({
        line = 1,
        text = case.expected
      }, result)
    end)
  end

  it("works with minimal valid configuration", function()
    local bufnr = make_buf({"function test() end"})
    local func_info = { line = 1, name = "test" }
    
    -- Provider config with minimal required fields (no defaults in provider)
    local provider_config = {
      include = { "refs" },
      breakdown = false,
      labels = { refs = "refs" },
      icon_for_single = nil,
      inner_separator = ", ",
    }
    
    local result = nil
    usages_provider.handler(bufnr, func_info, provider_config, function(res)
      result = res
    end)
    
    eq({
      line = 1,
      text = "󰌹 5"
    }, result)
  end)

  it("works with default configuration from config.lua", function()
    -- Test that the provider works with the actual default config
    config.setup({}) -- Use defaults
    local opts = config.get()
    
    -- Find usages provider config
    local usages_config = nil
    for _, provider in ipairs(opts.providers) do
      if provider.name == "usages" then
        usages_config = provider
        break
      end
    end
    
    eq("table", type(usages_config))
    eq("usages", usages_config.name)
    eq(false, usages_config.enabled) -- disabled by default
    eq({ "refs", "impls", "defs" }, usages_config.include)
    eq(false, usages_config.breakdown)
    
    -- Test the provider with default config
    local bufnr = make_buf({"function test() end"})
    local func_info = { line = 1, name = "test" }
    
    local result = nil
    usages_provider.handler(bufnr, func_info, usages_config, function(res)
      result = res
    end)
    
    eq({
      line = 1,
      text = "󰌹 8" -- nerdfont enabled by default in test, shows icon only
    }, result)
  end)
end)