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
  handler = function(bufnr, func_info, provider_config, callback)
    -- bufnr: buffer number
    -- func_info: { line = number, name = string, character = number, range = table }
    -- provider_config: this provider's configuration from setup()
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

- **Parameters**: `(bufnr, func_info, provider_config, callback)`
- **Return**: Nothing (always use callback)
- **Callback**: Called with lens item `{ line = number, text = string }` or `nil`
- **provider_config**: Contains this provider's configuration options

### Examples

**Sync provider (immediate callback):**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  callback({ line = func_info.line, text = "📄 " .. line_count .. " lines" })
end
```

**Async provider (delayed callback):**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result)
    if result then
      callback({ line = func_info.line, text = "ℹ️ hover available" })
    else
      callback(nil)
    end
  end)
end
```

**Using provider config:**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  local threshold = provider_config.threshold or 10
  local count = get_some_count(func_info)
  
  if count > threshold then
    callback({ line = func_info.line, text = "⚠️ " .. count })
  else
    callback(nil)
  end
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