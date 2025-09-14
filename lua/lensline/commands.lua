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

-- Profile management functions
function M.switch_profile(profile_name)
    setup.switch_profile(profile_name)
    vim.notify(string.format("Switched to profile '%s'", profile_name), vim.log.levels.INFO)
end

function M.get_active_profile()
    return config.get_active_profile()
end

function M.list_profiles()
    return config.list_profiles()
end

function M.has_profile(profile_name)
    return config.has_profile(profile_name)
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
    -- Profile management commands
    vim.api.nvim_create_user_command("LenslineProfile", function(opts)
        local args = opts.fargs
        
        if #args == 0 then
            -- Show current profile and available profiles
            local current = config.get_active_profile()
            local available = config.list_profiles()
            
            if current then
                vim.notify(string.format("Current profile: %s", current), vim.log.levels.INFO)
                if #available > 1 then
                    vim.notify(string.format("Available profiles: %s", table.concat(available, ", ")), vim.log.levels.INFO)
                end
            elseif #available > 0 then
                vim.notify(string.format("Available profiles: %s", table.concat(available, ", ")), vim.log.levels.INFO)
            else
                vim.notify("No profiles configured", vim.log.levels.INFO)
            end
        elseif #args == 1 then
            -- Switch to specified profile
            local profile_name = args[1]
            
            if not config.has_profiles() then
                vim.notify("No profiles configured", vim.log.levels.WARN)
                return
            end
            
            if not config.has_profile(profile_name) then
                local available = table.concat(config.list_profiles(), ", ")
                vim.notify(string.format("Profile '%s' not found. Available: %s", profile_name, available), vim.log.levels.ERROR)
                return
            end
            
            M.switch_profile(profile_name)
        else
            vim.notify("Usage: :LenslineProfile [profile_name]", vim.log.levels.ERROR)
        end
    end, {
        desc = "Switch lensline profile or show current/available profiles",
        nargs = "?",
        complete = function()
            return config.list_profiles()
        end
    })
    
    vim.api.nvim_create_user_command("LenslineListProfiles", function()
        local profiles = config.list_profiles()
        local current = config.get_active_profile()
        
        if #profiles == 0 then
            vim.notify("No profiles configured", vim.log.levels.INFO)
            return
        end
        
        local output = {}
        for _, profile in ipairs(profiles) do
            if profile == current then
                table.insert(output, profile .. " (active)")
            else
                table.insert(output, profile)
            end
        end
        
        vim.notify(string.format("Profiles: %s", table.concat(output, ", ")), vim.log.levels.INFO)
    end, {
        desc = "List all available lensline profiles"
    })
    
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
end

return M