-- Reference Count Provider
-- Shows reference count for functions/methods using LSP
return {
  name = "ref_count",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    
    -- Use composable LSP utility
    utils.get_lsp_references(bufnr, func_info, function(references)
      if references then
        local ref_count = #references
        local icon = utils.if_nerdfont_else("󰌹 ", "")
        local suffix = utils.if_nerdfont_else("", " refs")
        callback({
          line = func_info.line,
          text = icon .. ref_count .. suffix
        })
      else
        callback(nil)
      end
    end)
  end
}