-- lens manager - orchestrates function discovery + provider data collection + rendering
-- this is the new central coordination point instead of having providers do everything

local M = {}

-- main orchestration function
-- replaces the direct provider calls from core.lua
function M.refresh_buffer_lenses(bufnr)
    local function_discovery = require("lensline.infrastructure.function_discovery")
    local providers = require("lensline.providers")
    local renderer = require("lensline.renderer")
    local debug = require("lensline.debug")
    
    debug.log_context("LensManager", "refreshing lenses for buffer " .. bufnr)
    
    -- step 1: discover functions once (infrastructure layer)
    function_discovery.discover_functions(bufnr, function(functions)
        debug.log_context("LensManager", "discovered " .. #functions .. " functions, now collecting data from providers")
        
        -- step 2: collect data from all providers using discovered functions
        providers.collect_lens_data_with_functions(bufnr, functions, function(lens_data)
            debug.log_context("LensManager", "collected data for " .. #lens_data .. " lenses, now rendering")
            
            -- step 3: render lenses
            renderer.render_buffer_lenses(bufnr, lens_data)
        end)
    end)
end

return M