-- Diagnostic Summary Provider
-- Aggregates and displays diagnostic counts per function
local config = require("lensline.config")

return {
  name = "diag_summary",
  event = { "DiagnosticChanged", "BufReadPost" },
  handler = function(bufnr, func_info, provider_config, callback)
    -- Buffer validation like other providers
    local utils = require("lensline.utils")
    if not utils.is_valid_buffer(bufnr) then
      callback(nil)
      return
    end

    -- Configuration with defaults - matches config.lua default
    local min_level = (provider_config and provider_config.min_level) or "WARN"

    -- Convert string levels to numeric if needed
    if type(min_level) == "string" then
      local level_map = {
        ERROR = vim.diagnostic.severity.ERROR,
        WARN = vim.diagnostic.severity.WARN,
        INFO = vim.diagnostic.severity.INFO,
        HINT = vim.diagnostic.severity.HINT,
      }
      min_level = level_map[min_level:upper()] or vim.diagnostic.severity.WARN
    end

    -- Get diagnostic icons based on nerdfonts config
    local opts = config.get()
    local diagnostic_icons = {
      [vim.diagnostic.severity.ERROR] = opts.style.use_nerdfont and "" or "E",
      [vim.diagnostic.severity.WARN] = opts.style.use_nerdfont and "" or "W",
      [vim.diagnostic.severity.INFO] = opts.style.use_nerdfont and "" or "I",
      [vim.diagnostic.severity.HINT] = opts.style.use_nerdfont and "" or "H",
    }

    -- Helper to check if diagnostic is within function range
    -- func_info.line and func_info.end_line are 1-based (converted from LSP 0-based)
    -- diagnostic.lnum is 0-based
    local function is_in_function_range(diagnostic, func_info)
      if not func_info.line then
        return false
      end

      local diag_line = diagnostic.lnum  -- 0-based
      local func_start_line = func_info.line - 1  -- Convert to 0-based
      local func_end_line = (func_info.end_line or func_info.line) - 1  -- Convert to 0-based

      -- Simple line-based range check
      return diag_line >= func_start_line and diag_line <= func_end_line
    end

    -- Format diagnostic counts into display string, filtering by min_level
    local function format_diagnostic_counts(counts, min_level)
      local parts = {}

      -- Show severities in order, only if count > 0 and severity meets min_level
      local severities = {
        vim.diagnostic.severity.ERROR,
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
        vim.diagnostic.severity.HINT,
      }

      for _, severity in ipairs(severities) do
        local count = counts[severity]
        -- Only show if count > 0 AND severity is at or above min_level (lower number = higher severity)
        if count and count > 0 and severity <= min_level then
          table.insert(parts, count .. diagnostic_icons[severity])
        end
      end

      if #parts == 0 then
        return nil
      end

      return table.concat(parts, " ") -- single space between different severities
    end

    -- Get all diagnostics for the buffer
    local diagnostics = vim.diagnostic.get(bufnr)

    -- Count diagnostics within this function
    local counts = {
      [vim.diagnostic.severity.ERROR] = 0,
      [vim.diagnostic.severity.WARN] = 0,
      [vim.diagnostic.severity.INFO] = 0,
      [vim.diagnostic.severity.HINT] = 0,
    }

    local total_count = 0
    local highest_severity = vim.diagnostic.severity.HINT

    for _, diagnostic in ipairs(diagnostics) do
      if is_in_function_range(diagnostic, func_info) then
        if counts[diagnostic.severity] then
          counts[diagnostic.severity] = counts[diagnostic.severity] + 1
          total_count = total_count + 1
          -- Track highest severity (lower number = higher severity)
          if diagnostic.severity < highest_severity then
            highest_severity = diagnostic.severity
          end
        end
      end
    end

    -- Check if we should show diagnostics based on min_level
    -- Only show if highest severity is at or above the minimum level
    if total_count == 0 or highest_severity > min_level then
      callback(nil)
      return
    end

    local text = format_diagnostic_counts(counts, min_level)
    if not text then
      callback(nil)
      return
    end

    local result = {
      line = func_info.line,
      text = text,
    }

    -- Always call callback (async-only)
    callback(result)
  end,
}
