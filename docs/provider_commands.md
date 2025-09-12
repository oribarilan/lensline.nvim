# Provider-Specific Commands

This document outlines the pattern for creating commands that are specific to individual providers in lensline.

## Design Pattern

When a provider has dedicated commands, those commands should only be registered when the provider is enabled. This prevents command space pollution and provides clear feedback to users.

## Implementation

### 1. Provider Enablement Check

Add a utility function to check if a provider is enabled:

```lua
-- Check if a specific provider is enabled
local function is_provider_enabled(provider_name)
    local providers = require("lensline.providers")
    local enabled_providers = providers.get_enabled_providers()
    return enabled_providers[provider_name] ~= nil
end
```

### 2. Conditional Command Registration

In `register_commands()`, conditionally register provider-specific commands:

```lua
-- Provider-specific commands (conditional)
if is_provider_enabled("provider_name") then
    vim.api.nvim_create_user_command("CommandName", function()
        M.command_function()
    end, {
        desc = "Command description"
    })
end
```

### 3. Graceful Command Function Handling

Provider command functions should check enablement and provide helpful feedback:

```lua
function M.provider_command()
    if not is_provider_enabled("provider_name") then
        vim.notify("Provider is disabled. Enable it in your lensline config.", vim.log.levels.WARN)
        return
    end
    
    -- Command logic here
end
```

## Benefits

1. **Clean command space**: Only relevant commands exist
2. **Clear feedback**: Users get helpful messages when providers are disabled
3. **Performance**: No unnecessary command processing
4. **Consistency**: Follows existing patterns (debug command)

## Example: Usages Provider

The usages provider demonstrates this pattern:

- **Command**: `LenslineUsagesToggle`
- **Function**: `toggle_usages()`
- **Behavior**: 
  - Only registered when usages provider is enabled
  - Shows warning message if called when provider is disabled
  - Prevents execution of toggle logic when disabled

## Runtime Behavior

- Commands are registered at plugin load time based on initial configuration
- Configuration changes after plugin load require Neovim restart to affect command registration
- This is intentional to maintain consistency and prevent runtime command registration issues

## Future Considerations

When adding new provider-specific commands:

1. Follow this conditional registration pattern
2. Add graceful handling in command functions
3. Document the commands in provider documentation
4. Consider if the command should be global or provider-specific