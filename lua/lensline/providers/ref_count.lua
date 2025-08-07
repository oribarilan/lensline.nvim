local lens_explorer = require("lensline.lens_explorer")

-- Reference Count Provider
-- Shows reference count for functions/methods using LSP
return {
  name = "ref_count",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local debug = require("lensline.debug")
    local config = require("lensline.config")
    
    -- Get LSP clients for this buffer
    local clients = lens_explorer.get_lsp_clients(bufnr)
    debug.log_context("LSP", "found " .. (clients and #clients or 0) .. " LSP clients")
    if not clients or #clients == 0 then
      debug.log_context("LSP", "no LSP clients available")
      callback(nil)
      return
    end

    -- Check if any LSP client supports references
    if not lens_explorer.has_lsp_capability(bufnr, "textDocument/references") then
      debug.log_context("LSP", "no LSP client supports textDocument/references")
      callback(nil)
      return
    end

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
      local ref_count = 0
      
      if result and type(result) == "table" then
        ref_count = #result
      elseif err then
        debug.log_context("LSP", "request error: " .. vim.inspect(err))
      end
      
      -- Create and return lens item via callback
      local opts = config.get()
      local icon = opts.style.use_nerdfont and "󰌹 " or ""
      callback({
        line = func_info.line,
        text = icon .. ref_count .. (opts.style.use_nerdfont and "" or " refs")
      })
    end)
  end
}