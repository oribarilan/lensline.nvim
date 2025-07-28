local config = require("lensline.config")
local utils = require("lensline.utils")

local M = {}

-- Available providers following the new architecture
M.available_providers = {
  ref_count = require("lensline.providers.ref_count"),
  last_author = require("lensline.providers.last_author"),
  complexity = require("lensline.providers.complexity"),
}

-- Global debounce timers for each provider
local debounce_timers = {}

-- Event listeners setup
local event_listeners = {}

-- Get enabled providers from config
function M.get_enabled_providers()
  local debug = require("lensline.debug")
  local opts = config.get()
  local enabled = {}
  
  debug.log_context("Providers", "getting enabled providers from config")
  debug.log_context("Providers", "available providers: " .. vim.inspect(vim.tbl_keys(M.available_providers)))
  
  for _, provider_config in ipairs(opts.providers) do
    local provider_name = provider_config.name
    local provider_module = M.available_providers[provider_name]
    
    debug.log_context("Providers", "checking provider: " .. provider_name)
    debug.log_context("Providers", "provider_module found: " .. tostring(provider_module ~= nil))
    debug.log_context("Providers", "enabled: " .. tostring(provider_config.enabled ~= false))
    
    if provider_module and provider_config.enabled ~= false then
      enabled[provider_name] = {
        module = provider_module,
        config = provider_config
      }
      debug.log_context("Providers", "enabled provider: " .. provider_name)
    end
  end
  
  debug.log_context("Providers", "total enabled providers: " .. vim.tbl_count(enabled))
  return enabled
end

-- Setup event listeners for all enabled providers
function M.setup_event_listeners()
  local enabled_providers = M.get_enabled_providers()
  
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
  for event, providers in pairs(all_events) do
    local group_name = "lensline_" .. event:lower()
    local group_id = vim.api.nvim_create_augroup(group_name, { clear = true })
    event_listeners[event] = group_id
    
    vim.api.nvim_create_autocmd(event, {
      group = group_id,
      callback = function(args)
        for _, provider_info in ipairs(providers) do
          M.trigger_provider(args.buf, provider_info.name, provider_info.provider, provider_info.config)
        end
      end,
    })
  end
end

-- Trigger a specific provider with debouncing
function M.trigger_provider(bufnr, provider_name, provider_module, provider_config)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  local debounce_key = provider_name .. "_" .. bufnr
  local debounce_delay = provider_module.debounce or 100
  
  -- Cancel existing timer
  if debounce_timers[debounce_key] then
    debounce_timers[debounce_key]:stop()
  end
  
  -- Create new debounced execution
  debounce_timers[debounce_key] = vim.loop.new_timer()
  debounce_timers[debounce_key]:start(debounce_delay, 0, function()
    vim.schedule(function()
      M.execute_provider(bufnr, provider_module, provider_config)
    end)
  end)
end

-- Execute a provider and render results
function M.execute_provider(bufnr, provider_module, provider_config)
  local debug = require("lensline.debug")
  
  debug.log_context("Providers", "executing provider " .. provider_module.name .. " for buffer " .. bufnr)
  
  if not utils.is_valid_buffer(bufnr) then
    debug.log_context("Providers", "buffer " .. bufnr .. " is not valid", "WARN")
    return
  end
  
  -- Find functions once for all providers
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(bufnr)
  local functions = utils.find_functions_in_range(bufnr, start_line, end_line)
  
  debug.log_context("Providers", "found " .. (functions and #functions or 0) .. " functions for provider " .. provider_module.name)
  
  if not functions or #functions == 0 then
    debug.log_context("Providers", "no functions found, skipping provider " .. provider_module.name)
    return
  end
  
  local lens_items = {}
  local pending_functions = #functions
  local completed = false
  
  -- Timeout safety net for async providers
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(5000, 0, function()
    timeout_timer:close()
    if not completed then
      completed = true
      debug.log_context("Providers", "provider " .. provider_module.name .. " timed out, rendering " .. #lens_items .. " items")
      vim.schedule(function()
        local renderer = require("lensline.renderer")
        renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
      end)
    end
  end)
  
  local function handle_function_result(lens_item)
    if completed then return end
    
    if lens_item then
      table.insert(lens_items, lens_item)
      debug.log_context("Providers", "provider " .. provider_module.name .. " returned lens item for line " .. lens_item.line)
    end
    
    pending_functions = pending_functions - 1
    if pending_functions == 0 and not completed then
      completed = true
      timeout_timer:close()
      debug.log_context("Providers", "provider " .. provider_module.name .. " completed all functions, rendering " .. #lens_items .. " items")
      local renderer = require("lensline.renderer")
      renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
    end
  end
  
  -- Call provider once per function
  for _, func_info in ipairs(functions) do
    debug.log_context("Providers", "calling provider " .. provider_module.name .. " for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    local success, result = pcall(provider_module.handler, bufnr, func_info, handle_function_result)
    
    if success then
      -- If provider returns result synchronously, handle it immediately
      if result then
        handle_function_result(result)
      end
      -- If result is nil, provider will call handle_function_result asynchronously
    else
      debug.log_context("Providers", "provider " .. provider_module.name .. " failed for function at line " .. func_info.line .. ": " .. tostring(result), "ERROR")
      -- Still count this as processed to avoid hanging
      handle_function_result(nil)
    end
  end
end

-- Collect all lens data from enabled providers (used by main renderer)
function M.collect_all_lens_data(bufnr, callback)
  local enabled_providers = M.get_enabled_providers()
  local all_lens_data = {}
  local pending_providers = vim.tbl_count(enabled_providers)
  
  if pending_providers == 0 then
    callback({})
    return
  end
  
  local callback_called = false
  
  -- Timeout safety
  vim.defer_fn(function()
    if not callback_called then
      callback_called = true
      callback(all_lens_data)
    end
  end, 2000)
  
  for name, provider_info in pairs(enabled_providers) do
    M.execute_provider_async(bufnr, provider_info.module, provider_info.config, function(lens_items)
      if lens_items then
        for _, item in ipairs(lens_items) do
          table.insert(all_lens_data, item)
        end
      end
      
      pending_providers = pending_providers - 1
      if pending_providers == 0 and not callback_called then
        callback_called = true
        -- Sort by line number
        table.sort(all_lens_data, function(a, b) return a.line < b.line end)
        callback(all_lens_data)
      end
    end)
  end
end

-- Async version of provider execution
function M.execute_provider_async(bufnr, provider_module, provider_config, callback)
  vim.schedule(function()
    local success, lens_items = pcall(function()
      return M.execute_provider_sync(bufnr, provider_module, provider_config)
    end)
    
    if success then
      callback(lens_items)
    else
      callback({})
    end
  end)
end

-- Synchronous provider execution (returns lens items)
function M.execute_provider_sync(bufnr, provider_module, provider_config)
  if not utils.is_valid_buffer(bufnr) then
    return {}
  end
  
  -- Find functions once
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(bufnr)
  local functions = utils.find_functions_in_range(bufnr, start_line, end_line)
  
  if not functions or #functions == 0 then
    return {}
  end
  
  local lens_items = {}
  
  -- Call provider for each function synchronously
  for _, func_info in ipairs(functions) do
    local success, result = pcall(provider_module.handler, bufnr, func_info)
    if success and result then
      table.insert(lens_items, result)
    end
  end
  
  return lens_items
end

return M