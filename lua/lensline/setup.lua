local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local providers = require("lensline.providers")
local debug = require("lensline.debug")

local M = {}

local autocmd_group = nil
local global_refresh_timer = nil

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

local function debounced_refresh_current()
    -- Stop any existing timer safely
    if global_refresh_timer then
        if not global_refresh_timer:is_closing() then
            global_refresh_timer:stop()
            global_refresh_timer:close()
        end
        global_refresh_timer = nil
    end
    
    -- Create new timer
    local opts = config.get()
    global_refresh_timer = vim.loop.new_timer()
    global_refresh_timer:start(opts.refresh.debounce_ms, 0, function()
        vim.schedule(function()
            global_refresh_timer:close()
            global_refresh_timer = nil
            local current_bufnr = vim.api.nvim_get_current_buf()
            if utils.is_valid_buffer(current_bufnr) then
                refresh_buffer(current_bufnr)
            end
        end)
    end)
end

local function on_buffer_event(bufnr)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    -- Use global debounced refresh for current buffer
    debounced_refresh_current()
end

local function cleanup_buffer(bufnr)
    -- Just clear the renderer for this buffer
    -- Global timer doesn't need per-buffer cleanup
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
            -- Stop global timer on vim exit safely
            if global_refresh_timer then
                if not global_refresh_timer:is_closing() then
                    global_refresh_timer:stop()
                    global_refresh_timer:close()
                end
                global_refresh_timer = nil
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
    
    -- Stop global timer safely
    if global_refresh_timer then
        if not global_refresh_timer:is_closing() then
            global_refresh_timer:stop()
            global_refresh_timer:close()
        end
        global_refresh_timer = nil
    end
    
    -- Clear all buffer renderers
    local buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            renderer.clear_buffer(bufnr)
        end
    end
end

return M