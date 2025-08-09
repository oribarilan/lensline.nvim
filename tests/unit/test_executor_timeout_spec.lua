local eq = assert.are.same

-- Test executor timeout path:
-- Forces provider to never invoke callback so timeout renders 0 items.
-- Paths exercised:
--   timeout timer branch ([lua/lensline/executor.lua:229]-[lua/lensline/executor.lua:248])
--   limits.should_skip_lenses check with zero lens_items ([lua/lensline/executor.lua:268])

local function with_stub(mod_name, stub, fn)
  local orig = package.loaded[mod_name]
  package.loaded[mod_name] = stub
  local ok, err = pcall(fn)
  package.loaded[mod_name] = orig
  if not ok then error(err) end
end

describe("executor provider timeout fallback rendering", function()
  local orig_new_timer

  before_each(function()
    -- Capture original timer and patch only provider timeout timers (>=4000ms, repeat 0)
    orig_new_timer = vim.loop.new_timer
    vim.loop.new_timer = function()
      local real_timer = orig_new_timer()
      local proxy = {}
      function proxy:start(timeout, repeat_interval, cb)
        if timeout >= 4000 and repeat_interval == 0 then
          -- Accelerate timeout to 10ms
          vim.defer_fn(function()
            cb()
          end, 10)
        else
          real_timer:start(timeout, repeat_interval, cb)
        end
      end
      function proxy:stop()
        if real_timer.stop then real_timer:stop() end
      end
      function proxy:close()
        if real_timer.close then real_timer:close() end
      end
      function proxy:is_closing()
        if real_timer.is_closing then return real_timer:is_closing() end
        return false
      end
      return proxy
    end
  end)

  after_each(function()
    if orig_new_timer then
      vim.loop.new_timer = orig_new_timer
    end
  end)

  it("renders empty lens set on timeout when provider never completes", function()
    -- Configure single provider
    local config = require("lensline.config")
    config.setup({
      providers = {
        { name = "p_timeout", enabled = true },
      },
      style = { use_nerdfont = false },
      debounce_ms = 5,
      limits = { max_lines = 1000, exclude = {}, exclude_gitignored = false, max_lenses = 50 },
    })

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "function a() end",
      "function b() end",
    })

    -- Functions discovered (2) so pending_functions will stay > 0
    local discovered_funcs = {
      { line = 1, end_line = 1, name = "a" },
      { line = 2, end_line = 2, name = "b" },
    }

    local render_calls = {}
    local should_skip_lenses_calls = 0

    -- Provider whose handler never calls callback and returns nothing (async path unresolved)
    local provider_mod = {
      name = "p_timeout",
      handler = function() end,  -- neither return value nor async callback
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
          -- Provide functions immediately
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

            -- Wait for timeout branch to trigger render (fast simulated)
            vim.wait(400, function()
              return #render_calls > 0
            end)

            -- Assertions
            eq(1, #render_calls)                          -- Only timeout render
            eq("p_timeout", render_calls[1].provider)
            eq(0, render_calls[1].count)                  -- No items collected (timeout path)
            assert.is_true(should_skip_lenses_calls >= 1)  -- limits consulted

            vim.api.nvim_buf_delete(buf, { force = true })
          end)
        end)
      end)
    end)
  end)
end)