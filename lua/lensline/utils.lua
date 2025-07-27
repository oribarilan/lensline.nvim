local M = {}

function M.debounce(fn, delay)
    local timer = vim.loop.new_timer()
    return function(...)
        local args = { ... }
        timer:stop()
        timer:start(delay, 0, function()
            vim.schedule(function()
                fn(unpack(args))
            end)
        end)
    end, timer  -- Return timer for proper cleanup
end

function M.is_valid_buffer(bufnr)
    return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

-- helper to get lsp clients  (works with newer and older nvim versions)
function M.get_lsp_clients(bufnr)
    if vim.lsp.get_clients then
        return vim.lsp.get_clients({ bufnr = bufnr })
    else
        return vim.lsp.get_active_clients({ bufnr = bufnr })
    end
end


return M