local M = {}

function M.debounce(fn, delay)
    local timer = nil
    return function(...)
        local args = { ... }
        if timer then
            vim.fn.timer_stop(timer)
        end
        timer = vim.fn.timer_start(delay, function()
            fn(unpack(args))
            timer = nil
        end)
    end
end

function M.is_valid_buffer(bufnr)
    return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

-- helper to get lsp clients (works with newer and older nvim versions)
function M.get_lsp_clients(bufnr)
    if vim.lsp.get_clients then
        return vim.lsp.get_clients({ bufnr = bufnr })
    else
        return vim.lsp.get_active_clients({ bufnr = bufnr })
    end
end

function M.format_reference_count(count)
    if count == 0 then
        return "no references"
    elseif count == 1 then
        return "1 reference"
    else
        return count .. " references"
    end
end

return M