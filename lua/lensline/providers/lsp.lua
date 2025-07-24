local utils = require("lensline.utils")

local M = {}

-- recursively extract function symbols from lsp document symbols
local function get_function_symbols(symbols, results)
    results = results or {}
    
    for _, symbol in ipairs(symbols) do
        -- check if this is a function, method or constructor
        if symbol.kind == vim.lsp.protocol.SymbolKind.Function or
           symbol.kind == vim.lsp.protocol.SymbolKind.Method or
           symbol.kind == vim.lsp.protocol.SymbolKind.Constructor then
            table.insert(results, {
                name = symbol.name,
                line = symbol.range.start.line,
                character = symbol.range.start.character,
            })
        end
        
        -- recurse into children if they exist
        if symbol.children then
            get_function_symbols(symbol.children, results)
        end
    end
    
    return results
end

local function collect_functions(bufnr, callback)
    local clients = utils.get_lsp_clients(bufnr)
    
    if not clients or #clients == 0 then
        callback({})
        return
    end
    
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
        
        callback(functions)
    end)
end

local function count_references(bufnr, position, callback)
    vim.lsp.buf_request_all(bufnr, "textDocument/references", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = position,
        context = { includeDeclaration = false }
    }, function(results)
        local total_count = 0
        
        -- count refs from all lsp clients
        for client_id, result in pairs(results) do
            if result.result and type(result.result) == "table" then
                total_count = total_count + #result.result
            end
        end
        
        callback(total_count)
    end)
end

function M.get_lens_data(bufnr, callback)
    if not utils.is_valid_buffer(bufnr) then
        callback({})
        return
    end
    
    collect_functions(bufnr, function(functions)
        if #functions == 0 then
            callback({})
            return
        end
        
        local lens_data = {}
        local pending_requests = #functions
        
        for _, func in ipairs(functions) do
            count_references(bufnr, {
                line = func.line,
                character = func.character
            }, function(count)
                table.insert(lens_data, {
                    line = func.line,
                    text_parts = { utils.format_reference_count(count) }
                })
                
                pending_requests = pending_requests - 1
                if pending_requests == 0 then
                    table.sort(lens_data, function(a, b) return a.line < b.line end)
                    callback(lens_data)
                end
            end)
        end
    end)
end

return M