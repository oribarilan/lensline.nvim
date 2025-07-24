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

-- debug function to test lsp provider directly
function M.debug_lsp()
    local lsp_provider = require("lensline.providers.lsp")
    local bufnr = vim.api.nvim_get_current_buf()
    
    print("lensline: Testing LSP provider for buffer", bufnr)
    lsp_provider.get_lens_data(bufnr, function(lens_data)
        print("lensline: Got lens data with", #lens_data, "entries")
        for i, lens in ipairs(lens_data) do
            print("lensline:", i, "Line", lens.line, "Text:", vim.inspect(lens.text_parts))
        end
    end)
end

return M