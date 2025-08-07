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

-- Function content extraction utility
function M.get_function_lines(bufnr, func_info)
    local start_line = func_info.line
    local end_line = func_info.end_line
    
    -- If we have end_line, use it directly
    if end_line then
        return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    end
    
    -- If no end_line, try to estimate it by finding the function body
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, -1, false)
    local brace_count = 0
    local found_opening = false
    local estimated_end = start_line
    
    for i, line in ipairs(lines) do
        -- Count braces to find function end
        local open_braces = select(2, line:gsub("[{(]", ""))
        local close_braces = select(2, line:gsub("[})]", ""))
        
        if open_braces > 0 then
            found_opening = true
        end
        
        if found_opening then
            brace_count = brace_count + open_braces - close_braces
            if brace_count <= 0 and i > 1 then
                estimated_end = start_line + i - 1
                break
            end
        end
        
        -- Safety limit to avoid analyzing huge chunks
        if i > 100 then
            estimated_end = start_line + i - 1
            break
        end
    end
    
    return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, estimated_end, false)
end

return M