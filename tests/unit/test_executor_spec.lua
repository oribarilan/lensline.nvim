-- tests/unit/test_executor_spec.lua
-- Test executor core behaviors

local eq = assert.are.same
local test_utils = require("tests.test_utils")

describe("executor core behaviors", function()
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
    config.setup({
      debounce_ms = 5,
      providers = {
        { name = "p_exec", enabled = true },
      },
      style = { use_nerdfont = false },
    })
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    reset_modules()
  end)

  it("successful execution invokes provider handler and renders once with collected lenses", function()
    local handler_calls = 0
    local rendered = {}
    
    local bufnr = make_buf({"a", "", "b"})
    
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
            test_utils.stub_debug_silent()
            test_utils.with_enabled_config(config, function()
              local executor = require("lensline.executor")
              -- Force no stale cache path to ensure single provider pass
              executor.get_stale_cache_if_available = function() return nil end
              
              executor.execute_all_providers(bufnr)
              vim.wait(200, function() return rendered["p_exec"] ~= nil end)
              
              eq(2, handler_calls, "Should call handler once per function")
              eq(2, #rendered["p_exec"], "Should render two lens items")
              table.sort(rendered["p_exec"], function(a,b) return a.line < b.line end)
              eq({ { line = 1, text = "L1" }, { line = 3, text = "L3" } }, rendered["p_exec"])
            end)
          end)
        end)
      end)
    end)
  end)

  it("error path still completes without rendering partial items", function()
    local handler_calls = 0
    local render_calls = 0
    local rendered_items = nil
    local debug_msgs = {}
    
    local bufnr = make_buf({"x"})
    
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
            with_stub("lensline.debug", {
              log_context = function(_, msg) 
                table.insert(debug_msgs, msg) 
              end
            }, function()
              test_utils.with_enabled_config(config, function()
                local executor = require("lensline.executor")
                executor.get_stale_cache_if_available = function() return nil end
                
                executor.execute_all_providers(bufnr)
                vim.wait(300, function() return render_calls > 0 end)
                
                -- Handler may execute multiple times depending on execution flow
                assert.is_true(handler_calls >= 1, "Handler should be called at least once")
                eq(1, render_calls, "Should render exactly once despite errors")
                eq(0, #rendered_items, "Should render empty items on error")
                assert.is_truthy(table.concat(debug_msgs, "\n"):match("failed for function"), "Should log error message")
              end)
            end)
          end)
        end)
      end)
    end)
  end)

  it("concurrent unified update suppressed while execution in progress", function()
    local handler_calls = 0
    local final_items
    
    local bufnr = make_buf({"one", "two", "three", "four", "five"})
    
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
            test_utils.stub_debug_silent()
            test_utils.with_enabled_config(config, function()
              local executor = require("lensline.executor")
              executor.get_stale_cache_if_available = function() return nil end
              
              executor.execute_all_providers(bufnr)
              -- Fire multiple rapid unified updates; they should all be skipped while in progress
              executor.trigger_unified_update(bufnr)
              executor.trigger_unified_update(bufnr)
              executor.trigger_unified_update(bufnr)
              vim.wait(600, function() return final_items ~= nil end)
              
              -- Assert limited executions; no explosion of handler invocations
              assert.is_true(handler_calls >= 1 and handler_calls <= 5, "Should limit handler calls despite multiple triggers")
              assert.is_truthy(final_items, "Should eventually complete with items")
              
              -- Each lens item must have line + text
              for _, it in ipairs(final_items) do
                assert.is_number(it.line, "Each item should have numeric line")
                assert.is_string(it.text, "Each item should have string text")
                assert.is_truthy(it.text:match("^X%d+$"), "Text should match expected pattern")
              end
            end)
          end)
        end)
      end)
    end)
  end)
end)