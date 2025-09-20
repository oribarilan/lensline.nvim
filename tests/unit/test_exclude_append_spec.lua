-- tests/unit/test_exclude_append_spec.lua
-- unit tests for exclude_append functionality

local eq = assert.are.same

describe("exclude_append configuration", function()
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

  it("has exclude_append in defaults", function()
    local opts = config.get()
    assert.is_not_nil(opts.limits.exclude_append)
    eq({}, opts.limits.exclude_append)
  end)

  it("appends patterns to default exclude list", function()
    config.setup({
      limits = {
        exclude_append = { "custom_build/**", "*.tmp" }
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should contain default patterns
    assert.is_true(vim.tbl_contains(exclude_list, ".git/**"))
    assert.is_true(vim.tbl_contains(exclude_list, "node_modules/**"))
    
    -- Should also contain appended patterns
    assert.is_true(vim.tbl_contains(exclude_list, "custom_build/**"))
    assert.is_true(vim.tbl_contains(exclude_list, "*.tmp"))
    
    -- exclude_append should be cleaned up after merge
    assert.is_nil(opts.limits.exclude_append)
  end)

  it("appends to custom exclude list when user overrides defaults", function()
    config.setup({
      limits = {
        exclude = { "node_modules/**", "dist/**" },  -- override defaults
        exclude_append = { "custom/**", "*.log" }    -- append to custom list
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should only have user's custom exclude + appended patterns
    eq({ "node_modules/**", "dist/**", "custom/**", "*.log" }, exclude_list)
    
    -- Should NOT contain default patterns like .git/**
    assert.is_false(vim.tbl_contains(exclude_list, ".git/**"))
    
    -- exclude_append should be cleaned up
    assert.is_nil(opts.limits.exclude_append)
  end)

  it("handles empty exclude_append gracefully", function()
    config.setup({
      limits = {
        exclude_append = {}
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should still have default patterns
    assert.is_true(vim.tbl_contains(exclude_list, ".git/**"))
    assert.is_true(vim.tbl_contains(exclude_list, "node_modules/**"))
    
    -- exclude_append should be cleaned up even when empty
    assert.is_nil(opts.limits.exclude_append)
  end)

  it("handles missing exclude_append field", function()
    config.setup({
      limits = {
        max_lines = 500  -- some other limits config
      }
    })
    
    local opts = config.get()
    
    -- Should still have default exclude patterns
    assert.is_true(vim.tbl_contains(opts.limits.exclude, ".git/**"))
    
    -- exclude_append should be nil (not present)
    assert.is_nil(opts.limits.exclude_append)
  end)

  it("works with profile configurations", function()
    config.setup({
      limits = {
        exclude_append = { "global_pattern/**" }
      },
      profiles = {
        {
          name = "dev",
          providers = {
            { name = "references", enabled = true }
          }
        }
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should have defaults + appended pattern
    assert.is_true(vim.tbl_contains(exclude_list, ".git/**"))  -- default
    assert.is_true(vim.tbl_contains(exclude_list, "global_pattern/**"))  -- appended
    
    -- Should be active profile
    eq("dev", config.get_active_profile())
  end)

  it("preserves order: base patterns first, then appended patterns", function()
    config.setup({
      limits = {
        exclude = { "first/**", "second/**" },
        exclude_append = { "third/**", "fourth/**" }
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should maintain order: base first, then appended
    eq({ "first/**", "second/**", "third/**", "fourth/**" }, exclude_list)
  end)

  it("handles duplicate patterns gracefully", function()
    config.setup({
      limits = {
        exclude = { "node_modules/**", "dist/**" },
        exclude_append = { "node_modules/**", "custom/**" }  -- duplicate pattern
      }
    })
    
    local opts = config.get()
    local exclude_list = opts.limits.exclude
    
    -- Should contain both instances (no deduplication)
    eq({ "node_modules/**", "dist/**", "node_modules/**", "custom/**" }, exclude_list)
  end)
end)

describe("exclude_append integration with limits", function()
  local config
  local limits

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    config = require("lensline.config")
    limits = require("lensline.limits")
  end

  before_each(function()
    reset_modules()
  end)

  after_each(function()
    reset_modules()
  end)

  it("appended patterns are used by limits checking", function()
    config.setup({
      limits = {
        exclude_append = { "test_exclude/**", "*.test_ext" }
      }
    })
    
    -- Create a mock buffer with a path that matches appended pattern
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/some/path/test_exclude/file.js")
    
    local should_skip, reason = limits.should_skip(bufnr)
    
    -- Should be excluded due to appended pattern
    assert.is_true(should_skip)
    assert.is_not_nil(reason:match("glob pattern"))
    
    -- Cleanup
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)
end)