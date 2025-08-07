-- Diagnostic Summary Provider
-- Aggregates and displays diagnostic counts per function
-- Reuses logic from the legacy diagnostics collector but in modern provider format

return {
  name = "diag_summary",
  event = { "DiagnosticChanged", "BufReadPost" },  -- BufReadPost avoids conflicts with buffer switching
  handler = function(bufnr, func_info, provider_config, callback)
    -- Buffer validation like other providers
    local utils = require("lensline.utils")
    if not utils.is_valid_buffer(bufnr) then
      callback(nil)
      return
    end

    local debug = require("lensline.debug")
    local config = require("lensline.config")

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
      [vim.diagnostic.severity.ERROR] = opts.style.use_nerdfont and "" or "E",
      [vim.diagnostic.severity.WARN] = opts.style.use_nerdfont and "" or "W",
      [vim.diagnostic.severity.INFO] = opts.style.use_nerdfont and "" or "I",
      [vim.diagnostic.severity.HINT] = opts.style.use_nerdfont and "" or "H",
    }

    -- Helper to check if diagnostic is within function range
    local function is_in_function_range(diagnostic, func_range)
      if not func_range then
        return false
      end

      local diag_line = diagnostic.lnum
      local diag_col = diagnostic.col or 0

      local start_line = func_range.start.line
      local end_line = func_range["end"].line
      local start_char = func_range.start.character
      local end_char = func_range["end"].character

      if diag_line > start_line and diag_line < end_line then
        return true
      elseif diag_line == start_line and diag_col >= start_char then
        return true
      elseif diag_line == end_line and diag_col <= end_char then
        return true
      end

      return false
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
      if is_in_function_range(diagnostic, func_info.range) then
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

    debug.log_context("DiagSummary", "found " .. total_count .. " diagnostics")

    -- Check if we should show diagnostics based on min_level
    -- Only show if highest severity is at or above the minimum level
    if total_count == 0 or highest_severity > min_level then
      debug.log_context("DiagSummary", "skipping - no diagnostics or below min_level")
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

