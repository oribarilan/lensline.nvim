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


-- Language-agnostic function discovery using LSP document symbols
function M.find_functions_in_range(bufnr, start_line, end_line)
  -- First try LSP document symbols (most reliable)
  local lsp_functions = M.find_functions_via_lsp(bufnr, start_line, end_line)
  if #lsp_functions > 0 then
    return lsp_functions
  end
  
  -- Fallback to treesitter with language-agnostic queries
  local ts_functions = M.find_functions_via_treesitter(bufnr, start_line, end_line)
  if #ts_functions > 0 then
    return ts_functions
  end
  
  -- Final fallback to regex patterns
  return M.find_functions_generic(bufnr, start_line, end_line)
end

-- Use LSP document symbols to find functions (most reliable approach)
function M.find_functions_via_lsp(bufnr, start_line, end_line)
  local clients = M.get_lsp_clients(bufnr)
  if not clients or #clients == 0 then
    return {}
  end
  
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr)
  }
  
  local results = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 2000)
  if not results then
    return {}
  end
  
  local functions = {}
  
  -- Process results from all clients
  for _, result in pairs(results) do
    if result.result then
      M.extract_symbols_recursive(result.result, functions, start_line, end_line)
    end
  end
  
  return functions
end

-- Recursively extract function/method symbols from LSP response
function M.extract_symbols_recursive(symbols, functions, start_line, end_line)
  for _, symbol in ipairs(symbols) do
    -- Check if this symbol is a function, method, or constructor
    local symbol_kinds = {
      [vim.lsp.protocol.SymbolKind.Function] = true,
      [vim.lsp.protocol.SymbolKind.Method] = true,
      [vim.lsp.protocol.SymbolKind.Constructor] = true,
    }
    
    if symbol_kinds[symbol.kind] then
      local line_num
      local end_line_num
      local character
      
      -- Handle both DocumentSymbol and SymbolInformation formats
      if symbol.range then
        -- DocumentSymbol format
        line_num = symbol.range.start.line + 1 -- Convert to 1-indexed
        end_line_num = symbol.range["end"].line + 1 -- Convert to 1-indexed
        character = symbol.range.start.character
      elseif symbol.location then
        -- SymbolInformation format
        line_num = symbol.location.range.start.line + 1
        end_line_num = symbol.location.range["end"].line + 1
        character = symbol.location.range.start.character
      end
      
      if line_num and line_num >= start_line and line_num <= end_line then
        table.insert(functions, {
          line = line_num,
          end_line = end_line_num,
          character = character,
          name = symbol.name,
          kind = symbol.kind
        })
      end
    end
    
    -- Recursively process children if they exist
    if symbol.children then
      M.extract_symbols_recursive(symbol.children, functions, start_line, end_line)
    end
  end
end

-- Language-agnostic treesitter approach using common patterns
function M.find_functions_via_treesitter(bufnr, start_line, end_line)
  if not vim.treesitter.get_parser then
    return {}
  end
  
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return {}
  end
  
  local lang = parser:lang()
  local functions = {}
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  
  -- Language-specific queries for better accuracy
  local language_queries = {
    python = [[
      (function_definition name: (identifier) @func.name) @func.def
      (async_function_definition name: (identifier) @func.name) @func.def
    ]],
    javascript = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_definition name: (property_identifier) @func.name) @func.def
      (arrow_function) @func.def
    ]],
    typescript = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_definition name: (property_identifier) @func.name) @func.def
      (arrow_function) @func.def
    ]],
    c_sharp = [[
      (method_declaration name: (identifier) @func.name) @func.def
      (constructor_declaration name: (identifier) @func.name) @func.def
      (operator_declaration) @func.def
    ]],
    java = [[
      (method_declaration name: (identifier) @func.name) @func.def
      (constructor_declaration name: (identifier) @func.name) @func.def
    ]],
    go = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_declaration name: (field_identifier) @func.name) @func.def
    ]],
    rust = [[
      (function_item name: (identifier) @func.name) @func.def
      (impl_item (function_item name: (identifier) @func.name)) @func.def
    ]],
    lua = [[
      (function_statement name: (identifier) @func.name) @func.def
      (local_function_statement name: (identifier) @func.name) @func.def
    ]]
  }
  
  local query_string = language_queries[lang]
  if not query_string then
    -- Generic fallback query that works for many C-style languages
    query_string = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_declaration name: (_) @func.name) @func.def
      (function_definition name: (identifier) @func.name) @func.def
    ]]
  end
  
  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query then
    return {}
  end
  
  for id, node, metadata in query:iter_captures(tree:root(), bufnr, start_line - 1, end_line) do
    if query.captures[id] == "func.def" then
      local row, col = node:start()
      local line_num = row + 1 -- Convert to 1-indexed
      
      if line_num >= start_line and line_num <= end_line then
        table.insert(functions, {
          line = line_num,
          character = col,
          node = node
        })
      end
    end
  end
  
  return functions
end

-- Enhanced generic function detection with more language patterns
function M.find_functions_generic(bufnr, start_line, end_line)
  local functions = {}
  
  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  
  -- Expanded patterns for more languages
  local patterns = {
    -- Python
    "^%s*def%s+([%w_]+)",
    "^%s*async%s+def%s+([%w_]+)",
    -- JavaScript/TypeScript
    "^%s*function%s+([%w_]+)",
    "^%s*([%w_]+)%s*:%s*function",
    "^%s*([%w_]+)%s*=%s*function",
    "^%s*([%w_]+)%s*=%s*%([^%)]*%)%s*=>",
    -- C#
    "^%s*public%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*private%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*protected%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*internal%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*static%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    -- Java
    "^%s*public%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    "^%s*private%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    "^%s*protected%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    -- Go
    "^%s*func%s+([%w_]+)",
    "^%s*func%s*%(.*%)%s*([%w_]+)",
    -- Rust
    "^%s*fn%s+([%w_]+)",
    "^%s*pub%s+fn%s+([%w_]+)",
    -- Lua
    "^%s*function%s+([%w_.]+)",
    "^%s*local%s+function%s+([%w_]+)",
  }
  
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(patterns) do
      local func_name = line:match(pattern)
      if func_name then
        local line_num = start_line + i - 1
        -- Try to find a better character position by locating the function name
        local char_pos = line:find(func_name, 1, true) or 0
        table.insert(functions, {
          line = line_num,
          character = char_pos - 1, -- Convert to 0-indexed
          name = func_name
        })
        break
      end
    end
  end
  
  return functions
end

return M