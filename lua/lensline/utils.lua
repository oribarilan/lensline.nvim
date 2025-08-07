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

-- Simple config accessors
function M.is_using_nerdfonts()
    local config = require("lensline.config")
    local opts = config.get()
    return opts.style.use_nerdfont or false
end

function M.if_nerdfont_else(nerdfont_value, fallback_value)
    return M.is_using_nerdfonts() and nerdfont_value or fallback_value
end

return M