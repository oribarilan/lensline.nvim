-- easy reference for discovering default collectors per provider
-- copy this file to your config if you want to see/modify defaults

local lsp = require("lensline.providers.lsp")
local diagnostics = require("lensline.providers.diagnostics")

-- see current defaults for each provider
print("=== LSP Provider Defaults ===")
for i, collector in ipairs(lsp.default_collectors) do
    print("  " .. i .. ": " .. tostring(collector))
end

print("\n=== Diagnostics Provider Defaults ===")
for i, collector in ipairs(diagnostics.default_collectors) do
    print("  " .. i .. ": " .. tostring(collector))
end

print("\n=== Available Collectors ===")
print("LSP:", vim.inspect(vim.tbl_keys(lsp.collectors)))
print("Diagnostics:", vim.inspect(vim.tbl_keys(diagnostics.collectors)))

-- example: how to use defaults in your config
local example_config = {
    providers = {
        lsp = {
            enabled = true,
            collectors = {
                -- option 1: use all defaults (this is automatic if you don't specify collectors)
                -- unpack(lsp.default_collectors),
                
                -- option 2: mix defaults with custom
                lsp.collectors.references,  -- built-in
                function(lsp_context, function_info)  -- custom
                    return "custom: %s", "example"
                end
            }
        },
        diagnostics = {
            enabled = true,
            collectors = {
                -- use default diagnostics collector
                diagnostics.collectors.function_level,
                -- add custom ones here...
            }
        }
    }
}

print("\n=== Example Config Structure ===")
print(vim.inspect(example_config))