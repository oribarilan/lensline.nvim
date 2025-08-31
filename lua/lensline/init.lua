local M = {}

local config = require("lensline.config")
local setup = require("lensline.setup")
local commands = require("lensline.commands")

function M.setup(opts)
    config.setup(opts or {})
    setup.initialize()
    commands.register_commands()
end

-- export all command functions 
M.enable = commands.enable
M.disable = commands.disable
M.show = commands.show
M.hide = commands.hide
M.toggle_view = commands.toggle_view
M.toggle_engine = commands.toggle_engine
M.toggle = commands.toggle
M.is_enabled = commands.is_enabled
M.is_visible = commands.is_visible
M.refresh = commands.refresh

return M