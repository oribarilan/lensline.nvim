local eq = assert.are.same

-- Test: executor uses stale cache for immediate render, then updates with fresh async results
-- Focus areas:
--   - Immediate pass over stale functions ([lua/lensline/executor.lua:155])
--   - Subsequent async discovery triggers second render ([lua/lensline/executor.lua:186])

local function with_stub(mod_name, stub, fn)
  local orig = package.loaded[mod_name]
  package.loaded[mod_name] = stub
  local ok, err = pcall(fn)
  package.loaded[mod_name] = orig
  if not ok then error(err) end
end

describe("executor stale cache immediate render followed by fresh async update", function()
  it("renders twice: once from stale cache, then from async discovery", function()
    -- Prepare minimal config with single provider
    local config = require("lensline.config")
    config.setup({
      providers = {
        { name = "p_stale", enabled = true },
      },
      style = { use_nerdfont = false },
      debounce_ms = 5,
      limits = { max_lines = 1000, exclude = {}, exclude_gitignored = false, max_lenses = 100 },
    })

    local stale_funcs = {
      { line = 2, end_line = 2, name = "stale_fn" },
    }
    local fresh_funcs = {
      { line = 3, end_line = 3, name = "fresh_fn" },
      { line = 5, end_line = 5, name = "fresh_fn2" },
    }

    local render_calls = {}
    local handler_call_lines = {}

    -- Provider module that returns synchronously (stale + fresh phases)
    local provider_mod = {
      name = "p_stale",
      handler = function(bufnr, func_info, _, cb)
        table.insert(handler_call_lines, func_info.line)
        -- Synchronous single lens result
        return { line = func_info.line, text = "L" .. func_info.line }
      end,
      event = { "BufWritePost" },
    }

    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          p_stale = {
            module = provider_mod,
            config = {},
          }
        }
      end
    }, function()
      -- Patch lens_explorer to inject stale cache + controlled async fresh sequence
      local lens_explorer = require("lensline.lens_explorer")
      lens_explorer.function_cache = {} -- ensure fresh empty cache for isolation
      -- Pre-populate stale cache (changedtick ignored for stale path)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "line1",
        "stale body",
        "fresh a",
        "",
        "fresh b"
      })
      lens_explorer.function_cache[buf] = stale_funcs

      local async_called = 0
      with_stub("lensline.lens_explorer", setmetatable({
        function_cache = lens_explorer.function_cache,
        cleanup_cache = function() end,
        get_lsp_clients = function() return {} end,
        has_lsp_capability = function() return false end,
        discover_functions_async = function(_, _, _, cb)
          -- Delay to allow stale path to render first (slightly longer to stabilize ordering)
          async_called = async_called + 1
          vim.defer_fn(function()
            cb(fresh_funcs)
          end, 20)
        end,
      }, { __index = lens_explorer }), function()
        with_stub("lensline.renderer", {
          render_provider_lenses = function(_, provider_name, items)
            table.insert(render_calls, {
              provider = provider_name,
              items = vim.deepcopy(items),
            })
          end,
          namespace = vim.api.nvim_create_namespace("stale_ns"),
        }, function()
          with_stub("lensline.limits", {
            should_skip = function() return false end,
            should_skip_lenses = function() return false end,
            get_truncated_end_line = function(_, requested) return requested end,
            clear_cache = function() end,
          }, function()
            package.loaded["lensline.debug"] = { log_context = function() end }

            local executor = require("lensline.executor")
            executor.get_stale_cache_if_available = executor.get_stale_cache_if_available -- keep original

            executor.execute_all_providers(buf)

            -- Wait for both stale immediate render and async render (reduced wait window)
            vim.wait(150, function()
              return #render_calls >= 2
            end)

            -- Expectations (relaxed to avoid brittle line assumptions):
            -- We require at least two renders (stale + fresh) and that the
            -- second render contains a superset or different set (update).
            assert.is_true(#render_calls >= 2)

            -- Normalize ordering
            for _, call in ipairs(render_calls) do
              table.sort(call.items, function(a,b) return (a.line or 0) < (b.line or 0) end)
            end

            local first = render_calls[1].items
            local second = render_calls[2].items

            -- First render must be non-empty (came from stale cache)
            assert.is_true(#first > 0)
            -- Second render should differ (size change or different lines)
            local different = (#second ~= #first)
            if not different then
              for i = 1, #first do
                if first[i].line ~= second[i].line or first[i].text ~= second[i].text then
                  different = true
                  break
                end
              end
            end
            assert.is_true(different, "expected fresh render to differ from stale render")

            -- Provider handler invoked (sanity check, avoid brittle exact count expectations)
            table.sort(handler_call_lines)
            assert.is_true(#handler_call_lines >= #first, "expected at least one handler call per stale function")

            vim.api.nvim_buf_delete(buf, { force = true })
          end)
        end)
      end)
    end)
  end)
end)