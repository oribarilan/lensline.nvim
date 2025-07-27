local M = {}

local config = require("lensline.config")
local setup = require("lensline.setup")

function M.setup(opts)
    config.setup(opts or {})
    setup.initialize()
    
    -- create the toggle command
    vim.api.nvim_create_user_command("LenslineToggle", function()
        M.toggle()
    end, {
        desc = "Toggle lensline functionality on/off"
    })
    
    -- create debug command to view debug logs
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

function M.enable()
    setup.enable()
end

function M.disable()
    setup.disable()
end

function M.toggle()
    if config.is_enabled() then
        M.disable()
        vim.notify("Lensline disabled", vim.log.levels.INFO)
    else
        M.enable()
        vim.notify("Lensline enabled", vim.log.levels.INFO)
    end
end

function M.is_enabled()
    return config.is_enabled()
end

function M.refresh()
    setup.refresh_current_buffer()
end

return M