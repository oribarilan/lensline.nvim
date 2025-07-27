local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local providers = require("lensline.providers")
local debug = require("lensline.debug")
local debounce = require("lensline.debounce")

local M = {}

local autocmd_group = nil
local provider_instances = {}

-- Initialize provider event-based refresh systems
local function setup_provider_refresh_systems()
    local opts = config.get()
    
    debug.log_context("Core", "setting up provider event-based refresh systems")
    
    -- Initialize each provider's refresh system
    for _, provider_config in ipairs(opts.providers) do
        local provider_type = provider_config.type
        
        -- Load the provider module
        local ok, provider = pcall(require, "lensline.providers." .. provider_type)
        if ok and provider.setup then
            debug.log_context("Core", "initializing " .. provider_type .. " provider refresh system")
            provider.setup(provider_config)
            provider_instances[provider_type] = provider
        else
            debug.log_context("Core", "provider " .. provider_type .. " does not support event-based refresh", "WARN")
        end
    end
    
    debug.log_context("Core", "all provider refresh systems initialized")
end

-- Cleanup function for buffer deletion
local function cleanup_buffer(bufnr)
    -- Clear renderer for this buffer
    renderer.clear_buffer(bufnr)
    
    -- Cancel any pending debounce timers for this buffer
    debounce.cancel_buffer_timers(bufnr)
    
    -- Clear cache for this buffer from all providers
    local cache_service = require("lensline.cache")
    cache_service.cache.invalidate_all(bufnr)
end

local function setup_autocommands()
    if autocmd_group then
        vim.api.nvim_del_augroup_by_id(autocmd_group)
    end
    
    autocmd_group = vim.api.nvim_create_augroup("lensline", { clear = true })
    
    -- Buffer cleanup on deletion
    vim.api.nvim_create_autocmd("BufDelete", {
        group = autocmd_group,
        callback = function(event)
            cleanup_buffer(event.buf)
        end,
    })
    
    -- Cleanup on vim exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = autocmd_group,
        callback = function()
            -- Cleanup all debounce timers
            debounce.cleanup_all()
            
            -- Clear all caches
            local cache_service = require("lensline.cache")
            cache_service.cleanup_all()
            
            -- Clear suppressed tokens
            config.clear_suppressed_tokens()
        end,
    })
    
    debug.log_context("Core", "core autocommands initialized (providers handle their own refresh events)")
    
    -- Set up delayed renderer autocommands to pick up async data
    M.setup_delayed_renderer_events()
end

-- Set up delayed renderer events to pick up async collector data
M.setup_delayed_renderer_events = function()
    local debounce = require("lensline.debounce")
    
    -- Create the augroup once
    local delayed_renderer_group = vim.api.nvim_create_augroup("lensline_delayed_renderer", { clear = true })
    
    -- Listen to same events as LSP provider, but with 1-second delay for async data
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "LspAttach", "LspDetach" }, {
        group = delayed_renderer_group,
        callback = function(args)
            if not utils.is_valid_buffer(args.buf) then
                return
            end
            
            -- Debounce with 1-second delay to allow async collectors to complete
            debounce.debounce("delayed_renderer", args.buf, function()
                debug.log_context("Core", string.format("delayed renderer refresh for buffer %s", args.buf))
                vim.schedule(function()
                    local lens_manager = require("lensline.core.lens_manager")
                    if lens_manager and lens_manager.refresh_buffer_lenses then
                        lens_manager.refresh_buffer_lenses(args.buf)
                    end
                end)
            end, 1000) -- 1-second delay for async data collection
        end,
    })
    
    -- Also listen to file events for git data
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = delayed_renderer_group,
        callback = function(args)
            if not utils.is_valid_buffer(args.buf) then
                return
            end
            
            -- Same 1-second delay for git async data
            debounce.debounce("delayed_renderer", args.buf, function()
                debug.log_context("Core", string.format("delayed renderer refresh for buffer %s (git)", args.buf))
                vim.schedule(function()
                    local lens_manager = require("lensline.core.lens_manager")
                    if lens_manager and lens_manager.refresh_buffer_lenses then
                        lens_manager.refresh_buffer_lenses(args.buf)
                    end
                end)
            end, 1000)
        end,
    })
    
    debug.log_context("Core", "delayed renderer events initialized")
end

function M.initialize()
    local opts = config.get()
    
    -- initialize debug system first
    debug.init()
    
    debug.log_context("Core", "initializing plugin with event-based refresh system")
    debug.log_context("Core", "config: " .. vim.inspect(opts))
    
    -- setup LSP log filtering (must be done before any LSP requests)
    config.setup_lsp_handlers()
    
    -- Setup core autocommands
    setup_autocommands()
    
    -- Initialize provider event-based refresh systems
    setup_provider_refresh_systems()
    
    local current_buf = vim.api.nvim_get_current_buf()
    debug.log_context("Core", "current buffer: " .. current_buf)
    
    if utils.is_valid_buffer(current_buf) then
        debug.log_context("Core", "triggering initial refresh for buffer " .. current_buf)
        -- Initial render using lens manager
        local lens_manager = require("lensline.core.lens_manager")
        lens_manager.refresh_buffer_lenses(current_buf)
    else
        debug.log_context("Core", "current buffer is not valid, skipping initial refresh", "WARN")
    end
end

function M.refresh_current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    if utils.is_valid_buffer(bufnr) then
        debug.log_context("Core", "manual refresh requested for buffer " .. bufnr)
        
        -- Clear all provider caches for this buffer to force fresh data
        local cache_service = require("lensline.cache")
        cache_service.cache.invalidate_all(bufnr)
        
        -- Trigger refresh for all providers
        for provider_type, provider in pairs(provider_instances) do
            if provider.refresh then
                provider.refresh(bufnr, {})
            end
        end
    end
end

function M.enable()
    config.set_enabled(true)
    M.initialize()
end

function M.disable()
    config.set_enabled(false)
    
    debug.log_context("Core", "disabling event-based refresh system")
    
    -- restore original LSP handlers
    config.restore_lsp_handlers()
    
    -- Cleanup autocommands
    if autocmd_group then
        vim.api.nvim_del_augroup_by_id(autocmd_group)
        autocmd_group = nil
    end
    
    -- Cleanup all debounce timers
    debounce.cleanup_all()
    
    -- Clear all caches
    local cache_service = require("lensline.cache")
    cache_service.cleanup_all()
    
    -- Clear provider instances
    provider_instances = {}
    
    -- Clear all buffer renderers
    local buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            renderer.clear_buffer(bufnr)
        end
    end
    
    debug.log_context("Core", "event-based refresh system disabled")
end

return M