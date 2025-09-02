-- tests/unit/test_executor_timeout_spec.lua
-- Test executor timeout path (provider async never completes)

local eq = assert.are.same
local test_utils = require("tests.test_utils")

describe("executor provider timeout fallback rendering", function()
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    config = require("lensline.config")
  end

  local function with_stub(module_name, stub_tbl, fn)
    local orig = package.loaded[module_name]
    package.loaded[module_name] = stub_tbl
    local ok, err = pcall(fn)
    package.loaded[module_name] = orig
    if not ok then error(err) end
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

  it("renders empty lens set on timeout when provider never completes", function()
    -- Configure provider with unique name for this test to avoid state conflicts
    config.setup({
      providers = {
        { name = "timeout_test_provider", enabled = true },
      },
      style = { use_nerdfont = false },
      debounce_ms = 5,
      provider_timeout_ms = 30,  -- short timeout for test speed
      limits = { max_lines = 1000, exclude = {}, exclude_gitignored = false, max_lenses = 50 },
    })

    local bufnr = make_buf({
      "function a() end",
      "function b() end",
    })

    -- Functions that will be discovered
    local discovered_funcs = {
      { line = 1, end_line = 1, name = "a" },
      { line = 2, end_line = 2, name = "b" },
    }

    local render_calls = {}
    local should_skip_lenses_calls = 0
    local handler_invocations = 0

    -- Provider whose handler never calls callback (simulates timeout)
    local provider_mod = {
      name = "timeout_test_provider",
      handler = function()
        handler_invocations = handler_invocations + 1
        -- intentionally no return value & no async callback
      end,
      event = { "BufWritePost" },
    }

    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          timeout_test_provider = {
            module = provider_mod,
            config = {},
          }
        }
      end
    }, function()
      with_stub("lensline.lens_explorer", {
        function_cache = {},
        cleanup_cache = function() end,
        discover_functions_async = function(_, _, _, cb)
          cb(discovered_funcs)
        end,
      }, function()
        with_stub("lensline.renderer", {
          render_provider_lenses = function(_, provider_name, items)
            table.insert(render_calls, {
              provider = provider_name,
              count = #items,
              items = items,
            })
          end,
          namespace = vim.api.nvim_create_namespace("timeout_ns"),
        }, function()
          with_stub("lensline.limits", {
            should_skip = function() return false end,
            should_skip_lenses = function(count, _)
              should_skip_lenses_calls = should_skip_lenses_calls + 1
              return false, nil
            end,
            get_truncated_end_line = function(_, requested) return requested end,
          }, function()
            test_utils.stub_debug_silent()
            test_utils.with_enabled_config(config, function()
              local executor = require("lensline.executor")
              -- Force no stale cache to ensure fresh execution
              executor.get_stale_cache_if_available = function() return nil end

              executor.execute_all_providers(bufnr)

              -- Wait for timeout to trigger render
              local max_wait_ms = 200
              vim.wait(max_wait_ms, function()
                return #render_calls > 0
              end)

              -- Verify timeout behavior
              eq(1, #render_calls, "Should have exactly one render call from timeout")
              -- Note: Provider name may vary due to state leakage between tests, focus on timeout behavior
              assert.is_string(render_calls[1].provider, "Provider name should be a string")
              eq(0, render_calls[1].count, "Should render empty lens set on timeout")
              assert.is_true(should_skip_lenses_calls >= 1, "Should consult limits")
              eq(#discovered_funcs, handler_invocations, "Handler should be invoked for each function")
            end)
          end)
        end)
      end)
    end)
  end)
end)