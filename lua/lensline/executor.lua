local config = require("lensline.config")
local utils = require("lensline.utils")
local lens_explorer = require("lensline.lens_explorer")

local M = {}

-- Global debounce timer for unified provider updates
local unified_debounce_timer = {}

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
  
  -- Cancel existing timer for this buffer
  if unified_debounce_timer[debounce_key] then
    unified_debounce_timer[debounce_key]:stop()
  end
  
  -- Create new debounced execution that triggers all providers
  unified_debounce_timer[debounce_key] = vim.loop.new_timer()
  unified_debounce_timer[debounce_key]:start(debounce_delay, 0, function()
    vim.schedule(function()
      M.execute_all_providers(bufnr)
    end)
  end)
end

-- Execute all enabled providers for a buffer
function M.execute_all_providers(bufnr)
  local debug = require("lensline.debug")
  debug.log_context("Executor", "executing all providers for buffer " .. bufnr)
  
  local providers = require("lensline.providers")
  local enabled_providers = providers.get_enabled_providers()
  
  -- PERFORMANCE FIX: Discover functions once for ALL providers using lens_explorer
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(bufnr)
  debug.log_context("Performance", "UNIFIED FUNCTION DISCOVERY START for buffer " .. bufnr)
  local functions = lens_explorer.discover_functions(bufnr, start_line, end_line)
  debug.log_context("Performance", "UNIFIED FUNCTION DISCOVERY COMPLETE - found " .. (functions and #functions or 0) .. " functions")
  
  if not functions or #functions == 0 then
    debug.log_context("Executor", "no functions found, skipping all providers")
    return
  end
  
  -- Pass the discovered functions to each provider
  for name, provider_info in pairs(enabled_providers) do
    M.execute_provider_with_functions(bufnr, provider_info.module, provider_info.config, functions)
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
      debug.log_context("Executor", "provider " .. provider_module.name .. " returned lens item for line " .. lens_item.line)
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
    local success, result = pcall(provider_module.handler, bufnr, func_info, handle_function_result)
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