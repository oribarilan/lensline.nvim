local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local providers = require("lensline.providers")
local debug = require("lensline.debug")

local M = {}

local autocmd_group = nil
local refresh_timers = {}

local function refresh_buffer(bufnr)
    debug.log_context("Core", "refresh_buffer called for buffer " .. bufnr)
    
    -- check if plugin is enabled
    if not config.is_enabled() then
        debug.log_context("Core", "plugin is disabled, skipping refresh")
        return
    end
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("Core", "buffer " .. bufnr .. " is not valid for refresh", "WARN")
        return
    end
    
    debug.log_context("Core", "using new lens manager for orchestration")
    
    -- clear cache for this buffer since content may have changed
    local lsp_provider = require("lensline.providers.lsp")
    lsp_provider.clear_cache(bufnr)
    
    -- use new lens manager for orchestration instead of direct provider calls
    local lens_manager = require("lensline.core.lens_manager")
    lens_manager.refresh_buffer_lenses(bufnr)
end

local function get_debounced_refresh(bufnr)
    if not refresh_timers[bufnr] then
        local opts = config.get()
        refresh_timers[bufnr] = utils.debounce(function()
            refresh_buffer(bufnr)
        end, opts.refresh.debounce_ms)
    end
    return refresh_timers[bufnr]
end

local function on_buffer_event(bufnr)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    -- global debouncing - single update for all providers
    local debounced_refresh = get_debounced_refresh(bufnr)
    debounced_refresh()
end

local function cleanup_buffer(bufnr)
    if refresh_timers[bufnr] then
        refresh_timers[bufnr] = nil
    end
    renderer.clear_buffer(bufnr)
end

local function setup_autocommands()
    if autocmd_group then
        vim.api.nvim_del_augroup_by_id(autocmd_group)
    end
    
    autocmd_group = vim.api.nvim_create_augroup("lensline", { clear = true })
    
    local opts = config.get()
    
    vim.api.nvim_create_autocmd(opts.refresh.events, {
        group = autocmd_group,
        callback = function(event)
            on_buffer_event(event.buf)
        end,
    })
    
    -- additional cache invalidation events
    vim.api.nvim_create_autocmd("LspDetach", {
        group = autocmd_group,
        callback = function(event)
            debug.log_context("Core", "lsp detach detected, clearing cache for buffer " .. event.buf)
            local lsp_provider = require("lensline.providers.lsp")
            lsp_provider.clear_cache(event.buf)
        end,
    })
    
    vim.api.nvim_create_autocmd("BufDelete", {
        group = autocmd_group,
        callback = function(event)
            cleanup_buffer(event.buf)
        end,
    })
    
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = autocmd_group,
        callback = function()
            for bufnr, _ in pairs(refresh_timers) do
                cleanup_buffer(bufnr)
            end
        end,
    })
end

function M.initialize()
    local opts = config.get()
    
    -- initialize debug system first
    debug.init()
    
    debug.log_context("Core", "initializing plugin with config: " .. vim.inspect(opts))
    
    setup_autocommands()
    
    local current_buf = vim.api.nvim_get_current_buf()
    debug.log_context("Core", "current buffer: " .. current_buf)
    
    if utils.is_valid_buffer(current_buf) then
        debug.log_context("Core", "triggering initial refresh for buffer " .. current_buf)
        on_buffer_event(current_buf)
    else
        debug.log_context("Core", "current buffer is not valid, skipping initial refresh", "WARN")
    end
end

function M.refresh_current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    on_buffer_event(bufnr)
end

function M.enable()
    config.set_enabled(true)
    M.initialize()
end

function M.disable()
    config.set_enabled(false)
    
    if autocmd_group then
        vim.api.nvim_del_augroup_by_id(autocmd_group)
        autocmd_group = nil
    end
    
    for bufnr, _ in pairs(refresh_timers) do
        cleanup_buffer(bufnr)
    end
    refresh_timers = {}
end

return M