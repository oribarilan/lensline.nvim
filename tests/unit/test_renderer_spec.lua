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
    local virt = m[4] and m[4].virt_lines
    local text = nil
    if virt and virt[1] and virt[1][1] then
      -- virt_lines = { { {text, hl}, {text2, hl2}, ... } }
      -- Our tests configure prefix empty and no indentation => single tuple
      text = table.concat(vim.tbl_map(function(t) return t[1] end, virt[1]), "")
    end
    by_line[lnum] = text
  end
  return by_line, marks
end

local function reset(providers)
  config.setup({
    providers = providers,
    style = { prefix = "", separator = " • ", highlight = "Comment", use_nerdfont = false },
  })
  renderer.provider_lens_data = {}
end

describe("renderer combined lenses", function()
  before_each(function()
    -- ensure isolated state each case
    renderer.provider_lens_data = {}
  end)

  it("merges multiple provider outputs preserving line ordering", function()
    reset({
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    local buf = new_buf({ "line1", "line2", "line3", "line4" })

    -- Provider 1 lenses on lines 2 and 4
    renderer.render_provider_lenses(buf, "p1", {
      { line = 2, text = "A2" },
      { line = 4, text = "A4" },
    })

    -- Provider 2 lens on line 3
    renderer.render_provider_lenses(buf, "p2", {
      { line = 3, text = "B3" },
    })

    local by_line = collect_extmarks(buf)
    eq("A2", by_line[2])
    eq("B3", by_line[3])
    eq("A4", by_line[4])

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("stable ordering when two providers share same line", function()
    reset({
      { name = "p1", enabled = true },
      { name = "p2", enabled = true },
    })
    local buf = new_buf({ "fn()", "body" })

    renderer.render_provider_lenses(buf, "p2", {
      { line = 2, text = "B" },
    })
    renderer.render_provider_lenses(buf, "p1", {
      { line = 2, text = "A" },
    })

    local by_line = collect_extmarks(buf)
    -- Order must follow providers array (p1 then p2) regardless of call sequence
    eq("A • B", by_line[2])

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("skips nil or malformed entries safely", function()
    reset({
      { name = "p1", enabled = true },
    })
    local buf = new_buf({ "alpha", "beta", "gamma" })

    renderer.render_provider_lenses(buf, "p1", {
      nil,
      { line = 2 },              -- missing text
      { text = "NO_LINE" },      -- missing line
      { line = 3, text = "G3" }, -- only valid
    })

    local by_line = collect_extmarks(buf)
    eq(nil, by_line[1])
    eq(nil, by_line[2])
    eq("G3", by_line[3])

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles empty provider result set without error", function()
    reset({
      { name = "p1", enabled = true },
    })
    local buf = new_buf({ "only" })

    renderer.render_provider_lenses(buf, "p1", {})
    local _, marks = collect_extmarks(buf)
    eq(0, #marks)

    -- second empty call should also be safe (no new extmarks, no error)
    renderer.render_provider_lenses(buf, "p1", {})
    local _, marks2 = collect_extmarks(buf)
    eq(0, #marks2)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)