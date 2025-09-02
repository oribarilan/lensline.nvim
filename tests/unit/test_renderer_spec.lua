-- tests/unit/test_renderer_spec.lua
-- unit tests for lensline.renderer (combined lens rendering)

local eq = assert.are.same

-- minimal debug stub to avoid noise
package.loaded["lensline.debug"] = { log_context = function() end }

describe("renderer combined lenses", function()
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") and name ~= "lensline.debug" then
        package.loaded[name] = nil
      end
    end
  end

  local function clear_all_module_state()
    -- Clear renderer state
    local renderer = require("lensline.renderer")
    renderer.provider_lens_data = {}
    renderer.provider_namespaces = {}
    
    -- Clear lens explorer state
    local lens_explorer = require("lensline.lens_explorer")
    if lens_explorer.function_cache then
      for k, _ in pairs(lens_explorer.function_cache) do
        lens_explorer.function_cache[k] = nil
      end
    end
    
    -- Clear blame cache if it exists
    local ok, blame_cache = pcall(require, "lensline.blame_cache")
    if ok and blame_cache.clear_cache then
      blame_cache.clear_cache()
    end
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  local function setup_config(providers)
    local config = require("lensline.config")
    config.setup({
      providers = providers,
      style = { prefix = "", separator = " • ", highlight = "Comment", use_nerdfont = false },
    })
  end

  local function collect_extmarks(bufnr)
    local renderer = require("lensline.renderer")
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
    local by_line = {}
    for _, m in ipairs(marks) do
      local lnum = m[2] + 1
      local virt = m[4] and m[4].virt_lines
      local text = nil
      if virt and virt[1] and virt[1][1] then
        -- combine text segments from virt_lines
        text = table.concat(vim.tbl_map(function(t) return t[1] end, virt[1]), "")
      end
      by_line[lnum] = text
    end
    return by_line, marks
  end

  before_each(function()
    reset_modules()
    clear_all_module_state()
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

  it("merges multiple provider outputs", function()
    setup_config({
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    
    local renderer = require("lensline.renderer")
    local buf = make_buf({ "line1", "line2", "line3", "line4" })

    -- clear any existing data
    renderer.provider_lens_data = {}

    -- provider 1 lenses on lines 2 and 4
    renderer.render_provider_lenses(buf, "p1", {
      { line = 2, text = "A2" },
      { line = 4, text = "A4" },
    })

    -- provider 2 lens on line 3
    renderer.render_provider_lenses(buf, "p2", {
      { line = 3, text = "B3" },
    })

    local by_line = collect_extmarks(buf)
    eq("A2", by_line[2])
    eq("B3", by_line[3])
    eq("A4", by_line[4])
  end)

  it("maintains provider order when sharing lines", function()
    setup_config({
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    
    local renderer = require("lensline.renderer")
    local buf = make_buf({ "fn()", "body" })

    renderer.provider_lens_data = {}

    renderer.render_provider_lenses(buf, "p2", {
      { line = 2, text = "B" },
    })
    renderer.render_provider_lenses(buf, "p1", {
      { line = 2, text = "A" },
    })

    local by_line = collect_extmarks(buf)
    -- order follows providers config (p1 then p2) regardless of call sequence
    eq("A • B", by_line[2])
  end)

  it("filters malformed entries", function()
    setup_config({
      { name = "p1", enabled = true },
    })
    
    local renderer = require("lensline.renderer")
    local buf = make_buf({ "alpha", "beta", "gamma" })

    renderer.provider_lens_data = {}

    renderer.render_provider_lenses(buf, "p1", {
      nil,
      { line = 2 },              -- missing text
      { text = "NO_LINE" },      -- missing line
      { line = 3, text = "G3" }, -- valid
    })

    local by_line = collect_extmarks(buf)
    eq(nil, by_line[1])
    eq(nil, by_line[2])
    eq("G3", by_line[3])
  end)

  it("handles empty provider results", function()
    setup_config({
      { name = "p1", enabled = true },
    })
    
    local renderer = require("lensline.renderer")
    local buf = make_buf({ "only" })

    renderer.provider_lens_data = {}

    renderer.render_provider_lenses(buf, "p1", {})
    local _, marks = collect_extmarks(buf)
    eq(0, #marks)

    -- second empty call should be safe
    renderer.render_provider_lenses(buf, "p1", {})
    local _, marks2 = collect_extmarks(buf)
    eq(0, #marks2)
  end)
end)