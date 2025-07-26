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

-- debug function to test lsp provider directly
function M.debug_lsp()
    local lsp_provider = require("lensline.providers.lsp")
    local bufnr = vim.api.nvim_get_current_buf()
    
    print("lensline: testing lsp provider for buffer", bufnr)
    lsp_provider.get_lens_data(bufnr, function(lens_data)
        print("lensline: got lens data with", #lens_data, "entries")
        for i, lens in ipairs(lens_data) do
            print("lensline:", i, "line", lens.line, "text:", vim.inspect(lens.text_parts))
        end
    end)
end

-- test manual reference request at cursor position
function M.test_manual_references()
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- use proper position params as per guidelines
    local params = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = false }
    
    print("lensline: manual test with proper params:", vim.inspect(params))
    
    vim.lsp.buf_request_all(bufnr, "textDocument/references", params, function(results)
        print("lensline: manual reference results:")
        for client_id, result in pairs(results) do
            if result.error then
                print("lensline: client", client_id, "error:", vim.inspect(result.error))
            elseif result.result then
                print("lensline: client", client_id, "found", #result.result, "references")
                for i, ref in ipairs(result.result) do
                    print("lensline:   ", i, vim.inspect(ref))
                end
            else
                print("lensline: client", client_id, "no result")
            end
        end
    end)
end

return M