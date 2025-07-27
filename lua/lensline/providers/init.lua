local config = require("lensline.config")
local utils = require("lensline.utils")

local M = {}

-- Available providers following the new architecture
M.available_providers = {
  lsp_references = require("lensline.providers.lsp"),
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
  
  -- Always process the entire file for better performance
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(bufnr)
  debug.log_context("Providers", "using full buffer range: " .. start_line .. "-" .. end_line)
  
  -- Execute provider handler with async callback support
  debug.log_context("Providers", "calling provider handler for " .. provider_module.name)
  
  local function render_callback(lens_items)
    if lens_items and #lens_items > 0 then
      debug.log_context("Providers", "provider " .. provider_module.name .. " async callback returned " .. #lens_items .. " lens items")
      local renderer = require("lensline.renderer")
      renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
    else
      debug.log_context("Providers", "provider " .. provider_module.name .. " async callback returned no items")
    end
  end
  
  local success, lens_items = pcall(provider_module.handler, bufnr, start_line, end_line, render_callback)
  
  if success then
    -- For sync providers, lens_items will be returned immediately
    if lens_items and #lens_items > 0 then
      debug.log_context("Providers", "provider " .. provider_module.name .. " returned " .. #lens_items .. " lens items synchronously")
      local renderer = require("lensline.renderer")
      renderer.render_provider_lenses(bufnr, provider_module.name, lens_items)
    else
      debug.log_context("Providers", "provider " .. provider_module.name .. " will provide results asynchronously")
    end
  else
    debug.log_context("Providers", "provider " .. provider_module.name .. " failed: " .. tostring(lens_items), "ERROR")
    vim.notify("Lensline: Provider " .. provider_module.name .. " failed: " .. tostring(lens_items), vim.log.levels.ERROR)
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
  
  -- Always process the entire file
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(bufnr)
  
  -- For sync execution, don't pass callback and expect immediate return
  return provider_module.handler(bufnr, start_line, end_line) or {}
end

return M