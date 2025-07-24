local M = {}

local config = require("lensline.config")
local core = require("lensline.core")

function M.setup(opts)
    config.setup(opts or {})
    core.initialize()
end

function M.disable()
    core.disable()
end

function M.refresh()
    core.refresh_current_buffer()
end

return M