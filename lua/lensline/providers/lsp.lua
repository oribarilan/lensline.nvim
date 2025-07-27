local utils = require("lensline.utils")

-- LSP References Provider
-- Shows reference count for functions/methods using LSP
return {
  name = "lsp_references",
  event = { "LspAttach", "BufWritePost" },
  debounce = 1000,
  only_visible = true,
  visible_padding = 50,
  handler = function(bufnr, start_line, end_line)
    local debug = require("lensline.debug")
    
    debug.log_context("LSP", "handler called for buffer " .. bufnr .. " range " .. start_line .. "-" .. end_line)
    
    -- Get LSP clients for this buffer
    local clients = utils.get_lsp_clients(bufnr)
    debug.log_context("LSP", "found " .. (clients and #clients or 0) .. " LSP clients")
    if not clients or #clients == 0 then
      debug.log_context("LSP", "no LSP clients available")
      return {}
    end

    -- Find function definitions in the visible range using improved detection
    local functions = utils.find_functions_in_range(bufnr, start_line, end_line)
    debug.log_context("LSP", "found " .. (functions and #functions or 0) .. " functions")
    if not functions or #functions == 0 then
      debug.log_context("LSP", "no functions found in range")
      return {}
    end

    local lens_items = {}
    
    for _, func in ipairs(functions) do
      debug.log_context("LSP", "processing function '" .. (func.name or "unknown") .. "' at line " .. func.line)
      
      local ref_count = 0
      local found_refs = false
      
      -- Use the precise character position from our improved function detection
      local char_pos = func.character or 0
      
      -- If we have a function name, try to find its exact position in the line
      if func.name then
        local line_content = vim.api.nvim_buf_get_lines(bufnr, func.line - 1, func.line, false)[1] or ""
        local name_start = line_content:find(func.name, 1, true)
        if name_start then
          char_pos = name_start - 1  -- Convert to 0-indexed
          debug.log_context("LSP", "found function name '" .. func.name .. "' at character " .. char_pos)
        end
      end
      
      -- Create LSP reference request
      local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = func.line - 1, character = char_pos }, -- LSP is 0-indexed
        context = { includeDeclaration = false }
      }
      
      debug.log_context("LSP", "requesting references at position " .. (func.line - 1) .. ":" .. char_pos)
      
      -- Get references from LSP
      local results = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, 2000)
      
      if results then
        for client_id, result in pairs(results) do
          if result.result and type(result.result) == "table" then
            local client_ref_count = #result.result
            ref_count = ref_count + client_ref_count
            if client_ref_count > 0 then
              found_refs = true
              debug.log_context("LSP", "client " .. client_id .. " found " .. client_ref_count .. " references")
            end
          elseif result.error then
            debug.log_context("LSP", "client " .. client_id .. " returned error: " .. vim.inspect(result.error))
          end
        end
      else
        debug.log_context("LSP", "no LSP response received for references request")
      end
      
      -- Fallback: if no references found and we have multiple character positions to try
      if not found_refs and func.character then
        local line_content = vim.api.nvim_buf_get_lines(bufnr, func.line - 1, func.line, false)[1] or ""
        
        -- Try a few strategic positions around the detected character position
        local fallback_positions = {
          func.character + 1,  -- One character after
          func.character + 2,  -- Two characters after
          line_content:find("[%w_]", func.character + 1) and (line_content:find("[%w_]", func.character + 1) - 1) or func.character,
        }
        
        for _, fallback_char in ipairs(fallback_positions) do
          if found_refs then break end
          
          local fallback_params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            position = { line = func.line - 1, character = fallback_char },
            context = { includeDeclaration = false }
          }
          
          debug.log_context("LSP", "trying fallback position " .. (func.line - 1) .. ":" .. fallback_char)
          
          local fallback_results = vim.lsp.buf_request_sync(bufnr, "textDocument/references", fallback_params, 1000)
          if fallback_results then
            for _, result in pairs(fallback_results) do
              if result.result and type(result.result) == "table" and #result.result > 0 then
                ref_count = math.max(ref_count, #result.result)
                found_refs = true
                debug.log_context("LSP", "fallback position found " .. #result.result .. " references")
                break
              end
            end
          end
        end
      end
      
      debug.log_context("LSP", "total references for function '" .. (func.name or "unknown") .. "' at line " .. func.line .. ": " .. ref_count)
      
      -- Create lens item
      table.insert(lens_items, {
        line = func.line,
        text = "󰌹 " .. ref_count
      })
    end
    
    return lens_items
  end
}