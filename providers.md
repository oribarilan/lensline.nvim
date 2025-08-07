# Providers

Guidelines for writing custom providers for `lensline.nvim`.

## Architecture

**lensline** uses a simple **Provider** architecture:

- **Providers** are self-contained modules that handle specific data sources (LSP, git, etc.)
- Each provider defines its own event triggers and data collection logic
- Providers operate independently, allowing for easy addition or removal
- All providers use a unified async callback pattern

## Provider API

A provider is a Lua module that returns a table with the following structure:

```lua
-- custom_provider.lua
return {
  name = "my_custom_provider",
  event = { "BufWritePost" },  -- events that trigger this provider
  handler = function(bufnr, func_info, callback)
    -- bufnr: buffer number
    -- func_info: { line = number, name = string, character = number, range = table }
    -- callback: function to call with result
    
    -- Your custom logic here
    local custom_data = get_my_custom_data(func_info)
    
    -- Always call callback with lens item or nil
    callback({
      line = func_info.line,
      text = "💩 " .. custom_data
    })
    -- or callback(nil) if no lens should be shown
  end
}
```

### Handler Function

- **Parameters**: `(bufnr, func_info, callback)`
- **Return**: Nothing (always use callback)
- **Callback**: Called with lens item `{ line = number, text = string }` or `nil`

### Examples

**Sync provider (immediate callback):**
```lua
handler = function(bufnr, func_info, callback)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  callback({ line = func_info.line, text = "📄 " .. line_count .. " lines" })
end
```

**Async provider (delayed callback):**
```lua
handler = function(bufnr, func_info, callback)
  vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result)
    if result then
      callback({ line = func_info.line, text = "ℹ️ hover available" })
    else
      callback(nil)
    end
  end)
end
```

## Registration

Add your custom provider to the registry:

```lua
-- Add your custom provider to the registry
local providers = require("lensline.providers")
providers.available_providers.my_custom_provider = require("path.to.custom_provider")

require("lensline").setup({
  providers = {
    { name = "ref_count", enabled = true },
    { name = "my_custom_provider", enabled = true },
  }
})
```