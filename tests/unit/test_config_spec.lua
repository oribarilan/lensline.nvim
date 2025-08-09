local eq = assert.are.same
local config = require("lensline.config")

describe("config.setup core behavior", function()
  it("overrides defaults (style.use_nerdfont = false)", function()
    config.setup({
      style = { use_nerdfont = false },
    })
    local opts = config.get()
    eq(false, opts.style.use_nerdfont)
    -- Unchanged default still present
    eq("Comment", opts.style.highlight)
  end)

  it("provider-specific config (complexity min_level) respected by handler", function()
    -- Set min_level high so simple function filtered out
    config.setup({
      providers = {
        { name = "complexity", enabled = true, min_level = "L" },
      },
    })

    local complexity = require("lensline.providers.complexity")
    -- Create simple small function buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "function foo()",
      "  return 1",
      "end",
    })

    -- func_info marks full function
    local func_info = { line = 1, end_line = 3, name = "foo" }
    local provider_cfg = config.get().providers[1]
    local called = 0
    local received = "unset"
    complexity.handler(buf, func_info, provider_cfg, function(res)
      called = called + 1
      received = res
    end)
    eq(1, called)
    eq(nil, received) -- filtered (label S but min_level L)

    -- Now lower min_level to S and expect a result
    config.setup({
      providers = {
        { name = "complexity", enabled = true, min_level = "S" },
      },
    })
    provider_cfg = config.get().providers[1]
    called = 0
    received = "unset"
    complexity.handler(buf, func_info, provider_cfg, function(res)
      called = called + 1
      received = res
    end)
    eq(1, called)
    -- Expect a table with line and text
    eq(1, received.line)
    assert.is_truthy(received.text:match("^Cx: %u$"))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("repeated setup calls update state idempotently", function()
    config.setup({ style = { prefix = "A" } })
    eq("A", config.get().style.prefix)
    -- Second setup changes prefix only
    config.setup({ style = { prefix = "B" } })
    local opts = config.get()
    eq("B", opts.style.prefix)
    -- Other defaults retained
    eq(" • ", opts.style.separator)
  end)

  it("defensive handling when called with empty table", function()
    config.setup({})
    local opts = config.get()
    -- Defaults intact
    eq(true, opts.style.use_nerdfont)
    -- Providers list present
    assert.is_true(#opts.providers >= 1)
  end)
end)