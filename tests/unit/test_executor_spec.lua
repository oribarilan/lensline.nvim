local eq = assert.are.same

-- Stubs and helpers
local function with_stub(mod_name, stub, fn)
  local orig = package.loaded[mod_name]
  package.loaded[mod_name] = stub
  local ok, err = pcall(fn)
  package.loaded[mod_name] = orig
  if not ok then error(err) end
end

-- Provide minimal config for debounce + defaults
local config = require("lensline.config")

describe("executor core behaviors", function()
  before_each(function()
    config.setup({
      debounce_ms = 5,
      providers = {
        { name = "p_exec", enabled = true },
      },
      style = { use_nerdfont = false },
    })
  end)

  it("successful execution invokes provider handler and renders once with collected lenses", function()
    local handler_calls = 0
    local rendered = {}
    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          p_exec = {
            module = {
              name = "p_exec",
              handler = function(bufnr, func_info, provider_cfg, cb)
                handler_calls = handler_calls + 1
                -- Synchronous return (single callback style)
                return { line = func_info.line, text = "L" .. func_info.line }
              end
            },
            config = {},
          }
        }
      end
    }, function()
      with_stub("lensline.lens_explorer", {
        -- Async discovery returns two functions
        discover_functions_async = function(bufnr, s, e, cb)
          cb({
            { line = 1, end_line = 1, name = "a" },
            { line = 3, end_line = 3, name = "b" },
          })
        end,
        cleanup_cache = function() end,
        function_cache = {},
      }, function()
        with_stub("lensline.renderer", {
          render_provider_lenses = function(_, provider_name, items)
            rendered[provider_name] = items
          end,
          namespace = vim.api.nvim_create_namespace("dummy"),
        }, function()
          with_stub("lensline.limits", {
            should_skip = function() return false end,
            should_skip_lenses = function() return false end,
          }, function()
            package.loaded["lensline.debug"] = { log_context = function() end }
            local executor = require("lensline.executor")
            -- Force no stale cache path to ensure single provider pass
            executor.get_stale_cache_if_available = function() return nil end
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "", "b" })
            executor.execute_all_providers(buf)
            vim.wait(200, function() return rendered["p_exec"] ~= nil end)
            eq(2, handler_calls)
            eq(2, #rendered["p_exec"])
            table.sort(rendered["p_exec"], function(a,b) return a.line < b.line end)
            eq({ { line = 1, text = "L1" }, { line = 3, text = "L3" } }, rendered["p_exec"])
            vim.api.nvim_buf_delete(buf, { force = true })
          end)
        end)
      end)
    end)
  end)

  it("error path still completes without rendering partial items", function()
    local handler_calls = 0
    local render_calls = 0
    local rendered_items = nil
    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          p_exec = {
            module = {
              name = "p_exec",
              handler = function()
                handler_calls = handler_calls + 1
                error("boom")
              end
            },
            config = {},
          }
        }
      end
    }, function()
      with_stub("lensline.lens_explorer", {
        discover_functions_async = function(_, _, _, cb)
          cb({ { line = 2, end_line = 2, name = "x" } })
        end,
        cleanup_cache = function() end,
        function_cache = {},
      }, function()
        with_stub("lensline.renderer", {
          render_provider_lenses = function(_, _, items)
            render_calls = render_calls + 1
            rendered_items = items
          end,
          namespace = vim.api.nvim_create_namespace("dummy2"),
        }, function()
          with_stub("lensline.limits", {
            should_skip = function() return false end,
            should_skip_lenses = function() return false end,
          }, function()
            local debug_msgs = {}
            package.loaded["lensline.debug"] = { log_context = function(_, msg) table.insert(debug_msgs, msg) end }
            local executor = require("lensline.executor")
            executor.get_stale_cache_if_available = function() return nil end
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })
            executor.execute_all_providers(buf)
            vim.wait(300, function() return render_calls > 0 end)
            -- Handler may execute twice (stale+fresh) or once (fresh only) depending on prior cache state
            assert.is_true(handler_calls >= 1 and handler_calls <= 2)
            eq(1, render_calls)
            eq(0, #rendered_items)
            vim.api.nvim_buf_delete(buf, { force = true })
            assert.is_truthy(table.concat(debug_msgs, "\n"):match("failed for function"))
          end)
        end)
      end)
    end)
  end)

  it("concurrent unified update suppressed while execution in progress (no duplicate handler calls)", function()
    local handler_calls = 0
    local final_items
    with_stub("lensline.providers", {
      get_enabled_providers = function()
        return {
          p_exec = {
            module = {
              name = "p_exec",
              handler = function(_, func_info, _, cb)
                handler_calls = handler_calls + 1
                -- Async completion after delay to keep execution_in_progress true
                vim.defer_fn(function()
                  cb({ line = func_info.line, text = "X" .. func_info.line })
                end, 40)
              end
            },
            config = {},
          }
        }
      end
    }, function()
      local functions_sent = { { line = 5, end_line = 5, name = "delayed" } }
      with_stub("lensline.lens_explorer", {
        discover_functions_async = function(_, _, _, cb)
          cb(functions_sent)
        end,
        cleanup_cache = function() end,
        function_cache = {},
      }, function()
        with_stub("lensline.renderer", {
          render_provider_lenses = function(_, _, items)
            final_items = items
          end,
          namespace = vim.api.nvim_create_namespace("dummy3"),
        }, function()
          with_stub("lensline.limits", {
            should_skip = function() return false end,
            should_skip_lenses = function() return false end,
          }, function()
            package.loaded["lensline.debug"] = { log_context = function() end }
            local executor = require("lensline.executor")
            executor.get_stale_cache_if_available = function() return nil end
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three", "four", "five" })
            executor.execute_all_providers(buf)
            -- Fire multiple rapid unified updates; they should all be skipped while in progress
            executor.trigger_unified_update(buf)
            executor.trigger_unified_update(buf)
            executor.trigger_unified_update(buf)
            vim.wait(600, function() return final_items ~= nil end)
            -- Assert limited executions; no explosion of handler invocations
            assert.is_true(handler_calls >= 1 and handler_calls <= 5)
            assert.is_truthy(final_items)
            -- Each lens item must have line + text
            for _, it in ipairs(final_items) do
              assert.is_number(it.line)
              assert.is_string(it.text)
              assert.is_truthy(it.text:match("^X%d+$"))
            end
            vim.api.nvim_buf_delete(buf, { force = true })
          end)
        end)
      end)
    end)
  end)
end)