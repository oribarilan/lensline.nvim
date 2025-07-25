-- shared function discovery service for all providers
-- no more duplicated function discovery logic across providers

local utils = require("lensline.utils")
local debug = require("lensline.debug")

local M = {}

-- recursively extract function symbols from lsp document symbols
-- this was duplicated in both lsp.lua and diagnostics.lua
local function extract_function_symbols(symbols, results)
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
                range = symbol.range  -- include full range for range-based collectors
            })
        end
        
        -- recurse into children if they exist
        if symbol.children then
            extract_function_symbols(symbol.children, results)
        end
    end
    
    return results
end

-- central function discovery - shared by all providers
-- this eliminates the duplication between lsp and diagnostics providers
function M.discover_functions(bufnr, callback)
    debug.log_context("FunctionDiscovery", "discovering functions for buffer " .. bufnr)
    
    local clients = utils.get_lsp_clients(bufnr)
    
    debug.log_context("FunctionDiscovery", "found " .. (clients and #clients or 0) .. " lsp clients")
    
    if not clients or #clients == 0 then
        debug.log_context("FunctionDiscovery", "no lsp clients available", "WARN")
        callback({})
        return
    end
    
    -- check if any client supports document symbols
    local supports_document_symbols = false
    for _, client in ipairs(clients) do
        if client.supports_method("textDocument/documentSymbol") then
            supports_document_symbols = true
            debug.log_context("FunctionDiscovery", "client " .. client.name .. " supports documentSymbol")
            break
        end
    end
    
    if not supports_document_symbols then
        debug.log_context("FunctionDiscovery", "no clients support textDocument/documentSymbol", "WARN")
        callback({})
        return
    end
    
    debug.log_lsp_request("textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, "FunctionDiscovery")
    
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, function(results)
        local functions = {}
        
        debug.log_context("FunctionDiscovery", "got document symbol results from " .. (results and vim.tbl_count(results) or 0) .. " clients")
        
        for client_id, result in pairs(results) do
            if result.error then
                debug.log_context("FunctionDiscovery", "client " .. client_id .. " returned error: " .. vim.inspect(result.error), "ERROR")
            elseif result.result then
                debug.log_context("FunctionDiscovery", "client " .. client_id .. " returned " .. #result.result .. " symbols")
                local symbols = extract_function_symbols(result.result)
                for _, symbol in ipairs(symbols) do
                    table.insert(functions, symbol)
                end
            else
                debug.log_context("FunctionDiscovery", "client " .. client_id .. " returned no result", "WARN")
            end
        end
        
        debug.log_context("FunctionDiscovery", "found " .. #functions .. " total functions")
        callback(functions)
    end)
end

return M