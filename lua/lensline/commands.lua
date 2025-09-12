-- Command handling and programmatic API for lensline
local M = {}

local config = require("lensline.config")
local setup = require("lensline.setup")

-- Engine control functions
function M.enable()
    setup.enable()
end

function M.disable()
    setup.disable()
end

-- Visual display control functions
function M.show()
    config.set_visible(true)
    setup.refresh_current_buffer()
end

function M.hide()
    config.set_visible(false)
    setup.refresh_current_buffer()
end

function M.toggle_view()
    if config.is_visible() then
        M.hide()
        vim.notify("Lensline hidden", vim.log.levels.INFO)
    else
        M.show()
        vim.notify("Lensline shown", vim.log.levels.INFO)
    end
end

function M.toggle_engine()
    if config.is_enabled() then
        M.disable()
        vim.notify("Lensline engine disabled", vim.log.levels.INFO)
    else
        M.enable()
        vim.notify("Lensline engine enabled", vim.log.levels.INFO)
    end
end

-- Deprecated toggle function for backward compatibility
function M.toggle()
    vim.notify("LenslineToggle is deprecated. Use :LenslineToggleView or :LenslineToggleEngine instead.", vim.log.levels.WARN)
    M.toggle_view()
end

function M.is_enabled()
    return config.is_enabled()
end

function M.is_visible()
    return config.is_visible()
end

function M.refresh()
    setup.refresh_current_buffer()
end

-- Check if a specific provider is enabled
local function is_provider_enabled(provider_name)
    local ok, providers = pcall(require, "lensline.providers")
    if not ok then
        return false -- If providers module can't be loaded, assume disabled
    end
    
    local ok2, enabled_providers = pcall(providers.get_enabled_providers)
    if not ok2 then
        return false -- If can't get enabled providers, assume disabled
    end
    
    return enabled_providers[provider_name] ~= nil
end

function M.toggle_usages()
    local config = require("lensline.config")
    local provider_enabled = is_provider_enabled("usages")
    
    -- Always allow toggle state change (for backward compatibility with tests)
    local expanded = config.toggle_usages_expanded()
    
    if not provider_enabled then
        vim.notify("Usages provider is disabled. Enable it in your lensline config.", vim.log.levels.WARN)
        return
    end
    
    -- Only show success messages and refresh if provider is enabled
    if expanded then
        vim.notify("Lensline usages expanded", vim.log.levels.INFO)
    else
        vim.notify("Lensline usages collapsed", vim.log.levels.INFO)
    end
    
    -- Use targeted usages provider refresh instead of full buffer refresh
    local executor = require("lensline.executor")
    local bufnr = vim.api.nvim_get_current_buf()
    executor.execute_usages_provider_only(bufnr)
end

-- user command

function M.register_commands()
    -- Engine control commands
    vim.api.nvim_create_user_command("LenslineEnable", function()
        M.enable()
    end, {
        desc = "Enable lensline engine (providers, autocommands, resources)"
    })
    
    vim.api.nvim_create_user_command("LenslineDisable", function()
        M.disable()
    end, {
        desc = "Disable lensline engine (providers, autocommands, resources)"
    })
    
    -- View control commands
    vim.api.nvim_create_user_command("LenslineShow", function()
        M.show()
    end, {
        desc = "Show lensline visual display"
    })
    
    vim.api.nvim_create_user_command("LenslineHide", function()
        M.hide()
    end, {
        desc = "Hide lensline visual display"
    })
    
    -- Toggle commands
    vim.api.nvim_create_user_command("LenslineToggleView", function()
        M.toggle_view()
    end, {
        desc = "Toggle lensline visual display (show/hide)"
    })
    
    vim.api.nvim_create_user_command("LenslineToggleEngine", function()
        M.toggle_engine()
    end, {
        desc = "Toggle lensline engine (enable/disable)"
    })
    
    -- Deprecated command for backward compatibility
    vim.api.nvim_create_user_command("LenslineToggle", function()
        M.toggle()
    end, {
        desc = "DEPRECATED: Use LenslineToggleView or LenslineToggleEngine instead"
    })
    
    -- Debug command (conditional)
    if config.get().debug_mode then
        vim.api.nvim_create_user_command("LenslineDebug", function()
            local debug = require("lensline.debug")
            local debug_file = debug.get_debug_file()
            if debug_file and vim.fn.filereadable(debug_file) == 1 then
                vim.cmd("tabnew " .. debug_file)
            else
                vim.notify("No debug file found. Make sure debug_mode = true in your config.", vim.log.levels.WARN)
            end
        end, {
            desc = "Open lensline debug log file"
        })
    end
    
    -- Usages toggle command (conditional)
    if is_provider_enabled("usages") then
        vim.api.nvim_create_user_command("LenslineUsagesToggle", function()
            M.toggle_usages()
        end, {
            desc = "Toggle lensline usages display between total count and breakdown"
        })
    end
end

return M