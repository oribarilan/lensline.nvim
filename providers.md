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
    -- func_info: { line = number, name = string, character = number, range = table, end_line = number? }
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
- **Debug logging**: Automatic - no need to add debug logging in provider handlers

### func_info Structure

The `func_info` parameter contains:
- **`line`**: Function start line number (1-based)
- **`name`**: Function name
- **`character`**: Character position in line
- **`range`**: LSP range object
- **`end_line`**: Function end line number (optional - may be `nil` if unknown)

**Note**: `end_line` may not always be available depending on the LSP server and language. Always check if it exists before using it.

### Utility Functions

For common provider patterns, use the utility functions:

```lua
local utils = require("lensline.utils")

-- Check if nerdfonts are enabled
if utils.is_using_nerdfonts() then
  -- nerdfonts enabled
end

-- Choose value based on nerdfont setting
local icon = utils.if_nerdfont_else("📏", "Lines:")

-- Get function content as array of lines (including signature)
local function_lines = utils.get_function_lines(bufnr, func_info)
local function_text = table.concat(function_lines, "\n")
```

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

### Built-in Providers

Built-in providers are automatically available:

```lua
require("lensline").setup({
  providers = {
    { name = "ref_count", enabled = true },
    { name = "last_author", enabled = true },
    { name = "complexity", enabled = true },
    { name = "diag_summary", enabled = true },
  }
})
```

### Inline Providers

For simple custom providers, define them directly in your config:

```lua
require("lensline").setup({
  providers = {
    { name = "ref_count", enabled = true },
    
    -- Simple line counter
    {
      name = "line_counter",
      enabled = true,
      event = { "BufWritePost", "TextChanged" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        local total_lines = vim.api.nvim_buf_line_count(bufnr)
        local func_lines = "?"
        
        if func_info.end_line then
          func_lines = func_info.end_line - func_info.line + 1
        end
        
        local icon = utils.if_nerdfont_else("📏 ", "Lines: ")
        callback({
          line = func_info.line,
          text = string.format("%s%s/%d", icon, func_lines, total_lines)
        })
      end
    },
    
    -- TODO counter example
    {
      name = "todo_counter",
      enabled = true,
      event = { "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        local function_lines = utils.get_function_lines(bufnr, func_info)
        local todos = 0
        
        for _, line in ipairs(function_lines) do
          if line:match("TODO") or line:match("FIXME") then
            todos = todos + 1
          end
        end
        
        if todos > 0 then
          local icon = utils.if_nerdfont_else("📝 ", "TODOs: ")
          callback({ line = func_info.line, text = icon .. todos .. " TODOs" })
        else
          callback(nil)
        end
      end
    }
  }
})
```

### External Provider Files

For complex providers, create separate files and register them:

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