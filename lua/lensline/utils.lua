local M = {}

-- Core Utilities

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

-- Style & Configuration Utilities

function M.is_using_nerdfonts()
    local config = require("lensline.config")
    local ok, opts = pcall(config.get)
    if not ok or type(opts) ~= "table" then
        return false
    end
    local style = opts.style or {}
    return style.use_nerdfont == true
end

function M.if_nerdfont_else(nerdfont_value, fallback_value)
    return M.is_using_nerdfonts() and nerdfont_value or fallback_value
end

-- Buffer & Function Analysis Utilities

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
        -- Count braces to find function end (simple heuristic; includes braces in comments/strings)
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

-- LSP Utilities

function M.has_lsp_references_capability(bufnr)
    local lens_explorer = require("lensline.lens_explorer")
    local clients = lens_explorer.get_lsp_clients(bufnr)
    if not clients or #clients == 0 then
        return false
    end
    return lens_explorer.has_lsp_capability(bufnr, "textDocument/references")
end

function M.get_lsp_references(bufnr, func_info, callback)
    local debug = require("lensline.debug")
    local lens_explorer = require("lensline.lens_explorer")
    
    -- Check LSP capability first
    if not M.has_lsp_references_capability(bufnr) then
        debug.log_context("LSP", "no LSP references capability available")
        callback(nil)
        return
    end
    
    -- Resolve function position
    local char_pos = func_info.character or 0
    
    -- If we have a function name, try to find its exact position in the line
    if func_info.name then
        local line_content = vim.api.nvim_buf_get_lines(bufnr, func_info.line - 1, func_info.line, false)[1] or ""
        local name_start = line_content:find(func_info.name, 1, true)
        if name_start then
            char_pos = name_start - 1  -- Convert to 0-indexed
            debug.log_context("LSP", "found function name '" .. func_info.name .. "' at character " .. char_pos)
        end
    end
    
    -- Create LSP reference request
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = func_info.line - 1, character = char_pos },
        context = { includeDeclaration = false }
    }
    
    debug.log_context("LSP", "requesting references at position " .. (func_info.line - 1) .. ":" .. char_pos)
    
    -- Make async LSP request
    vim.lsp.buf_request(bufnr, "textDocument/references", params, function(err, result, ctx)
        if result and type(result) == "table" then
            callback(result)  -- Return raw reference array
        else
            if err then
                debug.log_context("LSP", "request error: " .. vim.inspect(err))
            end
            callback(nil)
        end
    end)
end

return M