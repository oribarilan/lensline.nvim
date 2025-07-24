local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local providers = require("lensline.providers")

local M = {}

local autocmd_group = nil
local refresh_timers = {}

local function refresh_buffer(bufnr)
    local opts = config.get()
    
    if opts.debug_mode then
        print("lensline: refresh_buffer called for buffer", bufnr)
    end
    
    if not utils.is_valid_buffer(bufnr) then
        if opts.debug_mode then
            print("lensline: Buffer", bufnr, "is not valid for refresh")
        end
        return
    end
    
    if opts.debug_mode then
        print("lensline: Collecting lens data for buffer", bufnr)
    end
    
    -- collect lens data and render it
    providers.collect_lens_data(bufnr, function(lens_data)
        if opts.debug_mode then
            print("lensline: Rendering", #lens_data, "lenses for buffer", bufnr)
        end
        renderer.render_buffer_lenses(bufnr, lens_data)
    end)
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
    
    if opts.debug_mode then
        print("lensline: Initializing plugin with config:", vim.inspect(opts))
    end
    
    setup_autocommands()
    
    local current_buf = vim.api.nvim_get_current_buf()
    if opts.debug_mode then
        print("lensline: Current buffer:", current_buf)
    end
    
    if utils.is_valid_buffer(current_buf) then
        if opts.debug_mode then
            print("lensline: Triggering initial refresh for buffer", current_buf)
        end
        on_buffer_event(current_buf)
    else
        if opts.debug_mode then
            print("lensline: Current buffer is not valid, skipping initial refresh")
        end
    end
end

function M.refresh_current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    on_buffer_event(bufnr)
end

function M.disable()
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