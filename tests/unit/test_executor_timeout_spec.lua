local eq = assert.are.same

-- Test executor timeout path (provider async never completes)
-- Enhancements:
--  - Uses configurable provider_timeout_ms (override via config) instead of timer patch heuristics
--  - Asserts provider handler invoked for each function (verifies pending_functions & legit timeout)
--  - Reduced overall wait for faster suite execution
-- Paths exercised:
--   timeout timer branch ([lua/lensline/executor.lua:229]-[lua/lensline/executor.lua:248]) using config.provider_timeout_ms override
--   limits.should_skip_lenses check with zero lens_items ([lua/lensline/executor.lua:268])

local function with_stub(mod_name, stub, fn)
  local orig = package.loaded[mod_name]
  package.loaded[mod_name] = stub
  local ok, err = pcall(fn)
  package.loaded[mod_name] = orig
  if not ok then error(err) end
end

describe("executor provider timeout fallback rendering (configurable timeout)", function()
  it("renders empty lens set on timeout when provider never completes", function()
    -- Configure single provider with short provider_timeout_ms for deterministic test
    local config = require("lensline.config")
    config.setup({
      providers = {
        { name = "p_timeout", enabled = true },
      },
      style = { use_nerdfont = false },
      debounce_ms = 5,
      provider_timeout_ms = 30,  -- override (default 5000ms) to accelerate timeout path
      limits = { max_lines = 1000, exclude = {}, exclude_gitignored = false, max_lenses = 50 },
    })

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "function a() end",
      "function b() end",
    })

    -- Functions discovered (2) so pending_functions will stay > 0 (never decremented)
    local discovered_funcs = {
      { line = 1, end_line = 1, name = "a" },
      { line = 2, end_line = 2, name = "b" },
    }

    local render_calls = {}
    local should_skip_lenses_calls = 0
    local handler_invocations = 0

    -- Provider whose handler never calls callback and returns nothing (async path unresolved)
    local provider_mod = {
      name = "p_timeout",
      handler = function()
        handler_invocations = handler_invocations + 1
        -- intentionally no return value & no async cb
      end,
      event = { "BufWritePost" },
    }

    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          p_timeout = {
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
          -- Provide functions immediately (no delay)
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
              -- never skip in this test
              return false, nil
            end,
            get_truncated_end_line = function(_, requested) return requested end,
          }, function()
            package.loaded["lensline.debug"] = { log_context = function() end }

            local executor = require("lensline.executor")
            -- Force no stale cache to avoid early rendering
            executor.get_stale_cache_if_available = function() return nil end

            executor.execute_all_providers(buf)

            -- Wait for timeout branch to trigger render (timeout_ms + safety margin)
            local max_wait_ms = 200
            vim.wait(max_wait_ms, function()
              return #render_calls > 0
            end)

            -- Assertions
            eq(1, #render_calls)                          -- Only timeout render
            eq("p_timeout", render_calls[1].provider)
            eq(0, render_calls[1].count)                  -- No items collected (timeout path)
            assert.is_true(should_skip_lenses_calls >= 1) -- limits consulted
            eq(#discovered_funcs, handler_invocations)    -- handler invoked once per discovered function

            vim.api.nvim_buf_delete(buf, { force = true })
          end)
        end)
      end)
    end)
  end)
end)