local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")

local M = {}

-- diagnostic severity icons/symbols
local severity_symbols = {
    [vim.diagnostic.severity.ERROR] = "E",
    [vim.diagnostic.severity.WARN] = "W", 
    [vim.diagnostic.severity.INFO] = "I",
    [vim.diagnostic.severity.HINT] = "H",
}

-- helper function to count diagnostics by severity for a specific line
local function count_diagnostics_for_line(bufnr, line)
    local diagnostics = vim.diagnostic.get(bufnr, { lnum = line })
    
    if not diagnostics or #diagnostics == 0 then
        return nil
    end
    
    local counts = {
        [vim.diagnostic.severity.ERROR] = 0,
        [vim.diagnostic.severity.WARN] = 0,
        [vim.diagnostic.severity.INFO] = 0,
        [vim.diagnostic.severity.HINT] = 0,
    }
    
    for _, diagnostic in ipairs(diagnostics) do
        if counts[diagnostic.severity] then
            counts[diagnostic.severity] = counts[diagnostic.severity] + 1
        end
    end
    
    return counts
end

-- helper function to format diagnostic counts into a string
local function format_diagnostic_counts(counts)
    local parts = {}
    
    -- add each severity type if count > 0, in order of severity
    local severities = {
        vim.diagnostic.severity.ERROR,
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
        vim.diagnostic.severity.HINT,
    }
    
    for _, severity in ipairs(severities) do
        local count = counts[severity]
        if count and count > 0 then
            table.insert(parts, count .. " " .. severity_symbols[severity])
        end
    end
    
    if #parts == 0 then
        return nil
    end
    
    return table.concat(parts, " ")
end

-- recursively extract function symbols from lsp document symbols (reusing LSP logic)
local function get_function_symbols(symbols, results)
    results = results or {}
    
    for _, symbol in ipairs(symbols) do
        -- check if this is a function, method or constructor
        if symbol.kind == vim.lsp.protocol.SymbolKind.Function or
           symbol.kind == vim.lsp.protocol.SymbolKind.Method or
           symbol.kind == vim.lsp.protocol.SymbolKind.Constructor then
            -- try to use selection range (function name) if available, fallback to range start
            local position
            if symbol.selectionRange then
                position = {
                    line = symbol.selectionRange.start.line,
                    character = symbol.selectionRange.start.character,
                }
            else
                position = {
                    line = symbol.range.start.line,
                    character = symbol.range.start.character,
                }
            end
            
            table.insert(results, {
                name = symbol.name,
                line = position.line,
                character = position.character,
                range = symbol.range, -- include full range for diagnostics aggregation
            })
        end
        
        -- recurse into children if they exist
        if symbol.children then
            get_function_symbols(symbol.children, results)
        end
    end
    
    return results
end

-- collect functions using LSP document symbols
local function collect_functions(bufnr, callback)
    local clients = utils.get_lsp_clients(bufnr)
    
    debug.log_context("Diagnostics", "Checking LSP clients for buffer " .. bufnr)
    
    if not clients or #clients == 0 then
        debug.log_context("Diagnostics", "No LSP clients available", "WARN")
        callback({})
        return
    end
    
    debug.log_context("Diagnostics", "Requesting document symbols for function detection")
    
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, function(results)
        local functions = {}
        
        for client_id, result in pairs(results) do
            if result.result then
                local symbols = get_function_symbols(result.result)
                for _, symbol in ipairs(symbols) do
                    table.insert(functions, symbol)
                end
            end
        end
        
        debug.log_context("Diagnostics", "Found " .. #functions .. " functions")
        callback(functions)
    end)
end

-- count diagnostics within a function's range
local function count_diagnostics_for_function(bufnr, func_range)
    local all_diagnostics = vim.diagnostic.get(bufnr)
    
    if not all_diagnostics or #all_diagnostics == 0 then
        return nil
    end
    
    local counts = {
        [vim.diagnostic.severity.ERROR] = 0,
        [vim.diagnostic.severity.WARN] = 0,
        [vim.diagnostic.severity.INFO] = 0,
        [vim.diagnostic.severity.HINT] = 0,
    }
    
    local total_count = 0
    
    for _, diagnostic in ipairs(all_diagnostics) do
        -- check if diagnostic is within function range
        local diag_line = diagnostic.lnum
        local diag_col = diagnostic.col or 0
        
        local in_range = false
        if func_range then
            local start_line = func_range.start.line
            local end_line = func_range["end"].line
            local start_char = func_range.start.character
            local end_char = func_range["end"].character
            
            if diag_line > start_line and diag_line < end_line then
                in_range = true
            elseif diag_line == start_line and diag_col >= start_char then
                in_range = true
            elseif diag_line == end_line and diag_col <= end_char then
                in_range = true
            end
        end
        
        if in_range and counts[diagnostic.severity] then
            counts[diagnostic.severity] = counts[diagnostic.severity] + 1
            total_count = total_count + 1
        end
    end
    
    if total_count == 0 then
        return nil
    end
    
    return counts
end

-- collect diagnostic data for functions
local function collect_function_diagnostics(bufnr, callback)
    debug.log_context("Diagnostics", "Collecting function diagnostics for buffer " .. bufnr)
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("Diagnostics", "Buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    collect_functions(bufnr, function(functions)
        if #functions == 0 then
            debug.log_context("Diagnostics", "No functions found, returning empty lens data")
            callback({})
            return
        end
        
        local lens_data = {}
        
        for _, func in ipairs(functions) do
            local counts = count_diagnostics_for_function(bufnr, func.range)
            if counts then
                local text = format_diagnostic_counts(counts)
                if text then
                    table.insert(lens_data, {
                        line = func.line,
                        character = func.character,
                        text_parts = { text }
                    })
                    debug.log_context("Diagnostics", "Function " .. func.name .. " has diagnostics: " .. text)
                end
            end
        end
        
        debug.log_context("Diagnostics", "Found diagnostics for " .. #lens_data .. " functions")
        callback(lens_data)
    end)
end

function M.get_lens_data(bufnr, callback)
    debug.log_context("Diagnostics", "get_lens_data called for buffer " .. bufnr)
    
    local opts = config.get()
    local diagnostics_config = opts.providers.diagnostics
    
    -- check if diagnostics provider is enabled (defaults to true)
    local provider_enabled = true
    if diagnostics_config and diagnostics_config.enabled ~= nil then
        provider_enabled = diagnostics_config.enabled
    end
    
    if not provider_enabled then
        debug.log_context("Diagnostics", "diagnostics provider is disabled")
        callback({})
        return
    end
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("Diagnostics", "buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    collect_function_diagnostics(bufnr, callback)
end

return M