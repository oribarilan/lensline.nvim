# Providers

Guidelines for writing custom providers for `lensline.nvim`.

## Architecture: Simple Providers

**lensline** uses a simple **Provider** architecture:

- **Providers** are self-contained modules that handle specific data sources (LSP, git, etc.)
- Each provider defines its own event triggers, debounce timing, and data collection logic
- Providers operate independently, allowing for easy addition or removal
- Providers are triggered per detected function, with a debounce mechanism to avoid excessive updates, and only on specific events in the active buffer


## Creating Custom Providers

You can create custom providers by adding them to the provider registry. A provider is a Lua module that returns a table with the following structure:

```lua
-- custom_provider.lua
return {
  name = "my_custom_provider",
  event = { "BufWritePost" },  -- events that trigger this provider
  debounce = 1000,             -- debounce delay in milliseconds
  handler = function(bufnr, func_info, callback)
    -- bufnr: buffer number
    -- func_info: { line = number, name = string, character = number }
    -- callback: function to call with result (for async) or nil (for sync)
    
    -- Your custom logic here
    local custom_data = get_my_custom_data(func_info)
    
    -- For synchronous providers, return the lens item:
    if not callback then
      return {
        line = func_info.line,
        text = "💩 " .. custom_data
      }
    end
    
    -- For async providers, call the callback:
    callback({
      line = func_info.line,
      text = "💩 " .. custom_data
    })
    return nil
  end
}
```

Then register it in your configuration by adding it to the providers registry:

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