local utils = require("lensline.utils")
local config = require("lensline.config")

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
    local opts = config.get()
    local clients = utils.get_lsp_clients(bufnr)
    
    if opts.debug_mode then
        print("lensline: Checking LSP clients for buffer", bufnr)
        print("lensline: Found", clients and #clients or 0, "LSP clients")
    end
    
    if not clients or #clients == 0 then
        if opts.debug_mode then
            print("lensline: No LSP clients available")
        end
        callback({})
        return
    end
    
    if opts.debug_mode then
        print("lensline: Requesting document symbols from LSP")
    end
    
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, function(results)
        local functions = {}
        
        if opts.debug_mode then
            print("lensline: Got document symbol results from", results and vim.tbl_count(results) or 0, "clients")
        end
        
        for client_id, result in pairs(results) do
            if opts.debug_mode then
                if result.error then
                    print("lensline: Client", client_id, "returned error:", vim.inspect(result.error))
                elseif result.result then
                    print("lensline: Client", client_id, "returned", #result.result, "symbols")
                else
                    print("lensline: Client", client_id, "returned no result")
                end
            end
            
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
        context = { includeDeclaration = true }
    }, function(results)
        local total_count = 0
        
        -- count refs from all lsp clients
        for client_id, result in pairs(results) do
            if result.result and type(result.result) == "table" then
                total_count = total_count + #result.result
            elseif result.error then
                -- LSP error occurred, maybe log it
                total_count = 0
            end
        end
        
        -- subtract 1 to exclude the declaration itself
        total_count = math.max(0, total_count - 1)
        
        callback(total_count)
    end)
end

function M.get_lens_data(bufnr, callback)
    local opts = config.get()
    
    if opts.debug_mode then
        print("lensline: get_lens_data called for buffer", bufnr)
    end
    
    if not utils.is_valid_buffer(bufnr) then
        if opts.debug_mode then
            print("lensline: Buffer", bufnr, "is not valid")
        end
        callback({})
        return
    end
    
    collect_functions(bufnr, function(functions)
        local opts = config.get()
        
        if opts.debug_mode then
            print("lensline: Found functions:", #functions)
            for _, func in ipairs(functions) do
                print("lensline: Function:", func.name, "at line", func.line)
            end
        end
        
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
                if opts.debug_mode then
                    print("lensline: Function", func.name, "has", count, "references")
                end
                
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