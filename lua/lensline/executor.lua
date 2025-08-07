local config = require("lensline.config")
local utils = require("lensline.utils")
local lens_explorer = require("lensline.lens_explorer")

local M = {}

-- Global debounce timer for unified provider updates
local unified_debounce_timer = {}

-- Track execution state to prevent cascading/recursive calls
local execution_in_progress = {}

-- Event listeners setup
local event_listeners = {}

-- Setup event listeners for all enabled providers
function M.setup_event_listeners()
  local providers = require("lensline.providers")
  local enabled_providers = providers.get_enabled_providers()
  
  -- Clear existing listeners
  for _, group in pairs(event_listeners) do
    if group then
      vim.api.nvim_del_augroup_by_id(group)
    end
  end
  event_listeners = {}
  
  -- Collect all unique events
  local all_events = {}
  for name, provider_info in pairs(enabled_providers) do
    for _, event in ipairs(provider_info.module.event) do
      if not all_events[event] then
        all_events[event] = {}
      end
      table.insert(all_events[event], {
        name = name,
        provider = provider_info.module,
        config = provider_info.config
      })
    end
  end
  
  -- Setup listeners for each unique event
  for event, providers_for_event in pairs(all_events) do
    local group_name = "lensline_" .. event:lower()
    local group_id = vim.api.nvim_create_augroup(group_name, { clear = true })
    event_listeners[event] = group_id
    
    vim.api.nvim_create_autocmd(event, {
      group = group_id,
      callback = function(args)
        -- Trigger unified update for all providers instead of individual triggers
        M.trigger_unified_update(args.buf)
      end,
    })
  end
end

-- Trigger unified update for all enabled providers with unified debouncing
function M.trigger_unified_update(bufnr)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  -- Prevent recursive executions during active provider runs
  if execution_in_progress[bufnr] then
    local debug = require("lensline.debug")
    debug.log_context("Executor", "skipping unified update for buffer " .. bufnr .. " - execution already in progress")
    return
  end
  
  -- Check limits before any provider execution
  local limits = require("lensline.limits")
  local should_skip, reason = limits.should_skip(bufnr)
  if should_skip then
    local debug = require("lensline.debug")
    debug.log_context("Executor", "skipping unified update for buffer " .. bufnr .. ": " .. (reason or "unknown"))
    return
  end
  
  local debounce_key = "unified_" .. bufnr
  local opts = config.get()
  local debounce_delay = opts.debounce_ms or 500
  
  -- Cancel existing timer to prevent multiple debounced calls
  if unified_debounce_timer[debounce_key] then
    unified_debounce_timer[debounce_key]:stop()
    unified_debounce_timer[debounce_key]:close()
  end
  
  -- Create new debounced execution that triggers all providers
  unified_debounce_timer[debounce_key] = vim.loop.new_timer()
  unified_debounce_timer[debounce_key]:start(debounce_delay, 0, function()
    vim.schedule(function()
      -- Verify execution state hasn't changed during debounce delay
      if not execution_in_progress[bufnr] then
        M.execute_all_providers(bufnr)
      end
    end)
  end)
end

-- Helper function to get stale cache data for immediate rendering
function M.get_stale_cache_if_available(bufnr)
  local debug = require("lensline.debug")
  
  -- Access lens_explorer's cache directly for stale data
  -- This allows showing previous function data immediately while async refresh happens
  local lens_explorer = require("lensline.lens_explorer")
  
  -- Try to get any cached functions for this buffer (even if changedtick doesn't match)
  local function_cache = lens_explorer.function_cache or {}
  local cached_functions = function_cache[bufnr]
  
  if cached_functions and #cached_functions > 0 then
    local current_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
    debug.log_context("Performance", "STALE CACHE CHECK - buffer " .. bufnr .. " has " .. #cached_functions .. " cached functions (current changedtick: " .. current_changedtick .. ")")
    return cached_functions
  else
    debug.log_context("Performance", "STALE CACHE CHECK - buffer " .. bufnr .. " has no cached functions available")
    return nil
  end
end

-- Execute all enabled providers for a buffer
function M.execute_all_providers(bufnr)
  local debug = require("lensline.debug")
  
  -- Track execution state to prevent recursive provider calls
  if execution_in_progress[bufnr] then
    debug.log_context("Executor", "execution already in progress for buffer " .. bufnr .. ", skipping")
    return
  end
  
  execution_in_progress[bufnr] = true
  local total_execution_start_time = vim.loop.hrtime()
  debug.log_context("Executor", "executing all providers for buffer " .. bufnr)
  debug.log_context("Performance", "=== ASYNC EXECUTION FLOW START ===")
  
  -- Ensure execution state is cleared regardless of success/failure
  local function cleanup_execution()
    execution_in_progress[bufnr] = nil
  end
  
  -- Wrap execution in pcall to guarantee cleanup
  local success, err = pcall(function()
    local providers = require("lensline.providers")
    local enabled_providers = providers.get_enabled_providers()
    
    -- PERFORMANCE FIX: Discover functions once for ALL providers using async lens_explorer
    local start_line = 1
    local end_line = vim.api.nvim_buf_line_count(bufnr)
    
    -- Try to show stale cache immediately for responsive UX
    local stale_start_time = vim.loop.hrtime()
    local stale_functions = M.get_stale_cache_if_available(bufnr)
    if stale_functions and #stale_functions > 0 then
      debug.log_context("Performance", "STALE CACHE RENDER START - found " .. #stale_functions .. " functions for immediate display")
      -- Execute providers with stale data for immediate feedback
      for name, provider_info in pairs(enabled_providers) do
        M.execute_provider_with_functions(bufnr, provider_info.module, provider_info.config, stale_functions)
      end
      local stale_end_time = vim.loop.hrtime()
      local stale_duration_ms = (stale_end_time - stale_start_time) / 1000000
      debug.log_context("Performance", "STALE CACHE RENDER COMPLETE - duration: " .. string.format("%.2f", stale_duration_ms) .. "ms")
    else
      debug.log_context("Performance", "NO STALE CACHE AVAILABLE - will wait for async result")
    end
    
    local async_start_time = vim.loop.hrtime()
    debug.log_context("Performance", "ASYNC FUNCTION DISCOVERY START for buffer " .. bufnr)
    lens_explorer.discover_functions_async(bufnr, start_line, end_line, function(functions)
      local async_end_time = vim.loop.hrtime()
      local async_duration_ms = (async_end_time - async_start_time) / 1000000
      debug.log_context("Performance", "ASYNC FUNCTION DISCOVERY COMPLETE - found " .. (functions and #functions or 0) .. " functions, total async duration: " .. string.format("%.2f", async_duration_ms) .. "ms")
      
      if not functions or #functions == 0 then
        debug.log_context("Executor", "no functions found in async result, skipping fresh providers")
        cleanup_execution()
        return
      end
      
      -- Pass the fresh discovered functions to each provider (will update stale lenses)
      local fresh_render_start_time = vim.loop.hrtime()
      debug.log_context("Performance", "FRESH DATA RENDER START - updating " .. #functions .. " functions")
      for name, provider_info in pairs(enabled_providers) do
        M.execute_provider_with_functions(bufnr, provider_info.module, provider_info.config, functions)
      end
      local fresh_render_end_time = vim.loop.hrtime()
      local fresh_render_duration_ms = (fresh_render_end_time - fresh_render_start_time) / 1000000
      debug.log_context("Performance", "FRESH DATA RENDER COMPLETE - duration: " .. string.format("%.2f", fresh_render_duration_ms) .. "ms")
      
      -- Log overall execution summary
      local total_execution_end_time = vim.loop.hrtime()
      local total_duration_ms = (total_execution_end_time - total_execution_start_time) / 1000000
      debug.log_context("Performance", "=== ASYNC EXECUTION FLOW COMPLETE - total duration: " .. string.format("%.2f", total_duration_ms) .. "ms ===")
      
      -- Clear execution state after triggering all providers
      cleanup_execution()
    end)
  end)
  
  if not success then
    debug.log_context("Executor", "error during provider execution: " .. tostring(err), "ERROR")
    cleanup_execution()
  end
end

-- Execute a provider with pre-discovered functions (OPTIMIZED VERSION)
function M.execute_provider_with_functions(bufnr, provider_module, provider_config, functions)
  local debug = require("lensline.debug")
  
  debug.log_context("Performance", "PROVIDER EXECUTION START - " .. provider_module.name .. " for buffer " .. bufnr .. " (with pre-discovered functions)")
  debug.log_context("Executor", "executing provider " .. provider_module.name .. " for buffer " .. bufnr)
  
  if not utils.is_valid_buffer(bufnr) then
    debug.log_context("Executor", "buffer " .. bufnr .. " is not valid", "WARN")
    return
  end
  
  debug.log_context("Executor", "using " .. #functions .. " pre-discovered functions for provider " .. provider_module.name)
  
  local lens_items = {}
  local pending_functions = #functions
  local completed = false
  
  -- Timeout safety net for async providers
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(5000, 0, function()
    timeout_timer:close()
    if not completed then
      completed = true
      debug.log_context("Executor", "provider " .. provider_module.name .. " timed out, rendering " .. #lens_items .. " items")
      vim.schedule(function()
        -- Check lens count limits before rendering (timeout case)
        local limits = require("lensline.limits")
        local config_opts = config.get()
        local should_skip_lenses, lens_reason = limits.should_skip_lenses(#lens_items, config_opts)
        
        if should_skip_lenses then
          debug.log_context("Executor", "skipping lens rendering for " .. provider_module.name .. " (timeout): " .. lens_reason)
          return
        end
        
        local renderer = require("lensline.renderer")
        renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
      end)
    end
  end)
  
  local function handle_function_result(lens_item)
    if completed then return end
    
    if lens_item then
      table.insert(lens_items, lens_item)
      debug.log_context("Executor", provider_module.name .. " → " .. lens_item.text .. " (line " .. lens_item.line .. ")")
    else
      debug.log_context("Executor", provider_module.name .. " → nil")
    end
    
    pending_functions = pending_functions - 1
    if pending_functions == 0 and not completed then
      completed = true
      timeout_timer:close()
      debug.log_context("Executor", "provider " .. provider_module.name .. " completed all functions, rendering " .. #lens_items .. " items")
      
      -- Check lens count limits before rendering
      local limits = require("lensline.limits")
      local config_opts = config.get()
      local should_skip_lenses, lens_reason = limits.should_skip_lenses(#lens_items, config_opts)
      
      if should_skip_lenses then
        debug.log_context("Executor", "skipping lens rendering for " .. provider_module.name .. ": " .. lens_reason)
        return
      end
      
      local renderer = require("lensline.renderer")
      renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
    end
  end
  
  -- Call provider once per function
  for _, func_info in ipairs(functions) do
    debug.log_context("Executor", "calling provider " .. provider_module.name .. " for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    debug.log_context("Executor", "provider started " .. provider_module.name)
    local success, result = pcall(provider_module.handler, bufnr, func_info, provider_config, handle_function_result)
    debug.log_context("Executor", "provider finished " .. provider_module.name)
    
    if success then
      -- If provider returns result synchronously, handle it immediately
      if result then
        handle_function_result(result)
      end
      -- If result is nil, provider will call handle_function_result asynchronously
    else
      debug.log_context("Executor", "provider " .. provider_module.name .. " failed for function at line " .. func_info.line .. ": " .. tostring(result), "ERROR")
      -- Still count this as processed to avoid hanging
      handle_function_result(nil)
    end
  end
end

-- Cleanup function for unified debounce timers
function M.cleanup_debounce_timers()
  local debug = require("lensline.debug")
  debug.log_context("Executor", "cleaning up unified debounce timers")
  
  for key, timer in pairs(unified_debounce_timer) do
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
      debug.log_context("Executor", "cleaned up timer: " .. key)
    end
  end
  unified_debounce_timer = {}
  
  -- Clear execution state tracking
  execution_in_progress = {}
end

-- Cleanup function for event listeners
function M.cleanup_event_listeners()
  local debug = require("lensline.debug")
  debug.log_context("Executor", "cleaning up event listeners")
  
  for event, group_id in pairs(event_listeners) do
    if group_id then
      vim.api.nvim_del_augroup_by_id(group_id)
      debug.log_context("Executor", "cleaned up event listener: " .. event)
    end
  end
  event_listeners = {}
end

-- Main cleanup function called during disable
function M.cleanup()
  M.cleanup_debounce_timers()
  M.cleanup_event_listeners()
  
  -- Clean up function discovery cache from lens_explorer
  lens_explorer.cleanup_cache()
end

return M