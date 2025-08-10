-- Code Complexity Provider
-- Estimates code complexity using language-aware research-based heuristics

-- Language-specific patterns for better accuracy
local language_patterns = {
  lua = {
    -- 'else' removed: not a decision point
    control_flow = { "if", "elseif", "while", "for", "repeat" },
    loops = { "for", "while", "repeat" },
    exceptions = { "pcall", "xpcall", "error" },
    comments = { "%-%-" },
    weight = 1.0
  },
  javascript = {
    control_flow = { "if", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "while", "do", "forEach", "map", "filter", "reduce" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  typescript = {
    control_flow = { "if", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "while", "do", "forEach", "map", "filter", "reduce" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  python = {
    control_flow = { "if", "elif", "try", "except", "finally" },
    loops = { "for", "while" },
    exceptions = { "try", "except", "raise", "finally" },
    comments = { "#" },
    weight = 0.9
  },
  go = {
    control_flow = { "if", "switch", "case", "select" },
    loops = { "for", "range" },
    exceptions = { "defer", "panic", "recover" },
    comments = { "//" },
    weight = 1.0
  },
  rust = {
    control_flow = { "if", "match" },
    loops = { "for", "while", "loop" },
    exceptions = { "panic" }, -- panic! macro / function-like
    comments = { "//", "/%*" },
    weight = 1.0
  },
  cs = {
    control_flow = { "if", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "foreach", "while", "do" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  -- Alias: some setups may report 'csharp' instead of 'cs'
  csharp = {
    control_flow = { "if", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "foreach", "while", "do" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  default = {
    control_flow = { "if", "elif", "elseif", "switch", "case", "when" },
    loops = { "for", "while", "do", "each", "map", "filter" },
    exceptions = { "try", "catch", "except", "finally", "rescue" },
    comments = { "//", "#", "%-%-" },
    weight = 1.0
  }
}

local function format_complexity(label)
  return "Cx: " .. label
end

local function should_show_complexity(label, min_level)
  local level_values = { S = 1, M = 2, L = 3, XL = 4 }
  local current_value = level_values[label] or 0
  local min_value = level_values[min_level] or 3
  return current_value >= min_value
end

--- Enhanced complexity estimation with language awareness and single-pass parsing
---@param lines table Array of function lines
---@param filetype string Vim filetype for language-specific patterns
---@return string complexity_label, integer score
local function estimate_complexity(lines, filetype)
  local patterns = language_patterns[filetype] or language_patterns.default
  local LOC = #lines
  local max_indent = 0
  local branch_count, conditional_count, loop_count = 0, 0, 0

  for _, line in ipairs(lines) do
    local indent = line:match("^(%s*)") or ""
    max_indent = math.max(max_indent, #indent)

    local clean_line = line
    for _, comment_pattern in ipairs(patterns.comments) do
      clean_line = clean_line:gsub("%s*" .. comment_pattern .. ".*", "")
    end

    if clean_line:match("^%s*$") then
      goto continue
    end

    for _, pattern in ipairs(patterns.control_flow) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      -- Skip counting pure 'else' (we removed it from patterns, defensive guard if user adds back)
      if pattern ~= "else" then
        branch_count = branch_count + matches
      end
    end

    for _, pattern in ipairs(patterns.loops) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      loop_count = loop_count + matches
    end

    for _, pattern in ipairs(patterns.exceptions) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      branch_count = branch_count + matches
    end

    if clean_line:match("%f[%w_](if|while|elsif|elseif|elif)%f[%W_]") then
      -- Robust logical operator counting via token scan (avoids frontier edge cases)
      local conditionals = 0
      for token in clean_line:gmatch("%f[%w_](%a+)%f[%W_]") do
        if token == "and" or token == "or" or token == "not" then
          conditionals = conditionals + 1
        end
      end
      conditional_count = conditional_count + conditionals
    end

    ::continue::
  end

  -- Indentation contribution: only large when there is structural control flow.
  -- Purely indented sequential code should remain Small; cap modestly in that case.
  local structural_count = branch_count + loop_count + conditional_count
  local indent_component
  if structural_count == 0 then
    -- Cap at 0.4 (max_indent 4 * 0.1) to avoid inflating trivial functions
    indent_component = math.min(max_indent, 4) * 0.1
  else
    indent_component = max_indent * 0.5
  end

  local base_score =
    branch_count * 3.0 +
    loop_count * 4.0 +
    conditional_count * 2.0 +
    math.min(LOC, 30) * 0.1 +
    indent_component

  local score = base_score * patterns.weight

  local label
  if score <= 5 then
    label = "S"
  elseif score <= 12 then
    label = "M"
  elseif score <= 20 then
    label = "L"
  else
    label = "XL"
  end

  -- Post-adjustment: ensure minimal classification for any branching/conditionals
  if label == "S" and (branch_count > 0 or conditional_count > 0 or loop_count > 0) then
    label = "M"
  end

  return label, math.floor(score)
end

-- Expose for tests (intentionally leak minimal surface)
_G.estimate_complexity = estimate_complexity

local provider = {
  name = "complexity",
  event = { "BufWritePost", "TextChanged" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    if not utils.is_valid_buffer(bufnr) then
      callback(nil)
      return
    end

    local debug = require("lensline.debug")
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" then
      -- Allow unsaved buffers (complexity is content-based)
      debug.log_context("Complexity", "unsaved buffer - proceeding")
    end

    -- Refresh provider_config from global config if missing or stale
    if (not provider_config) or provider_config.name ~= "complexity" or provider_config.min_level == nil then
      local ok_cfg, cfg_mod = pcall(require, "lensline.config")
      if ok_cfg then
        local ok_get, global_cfg = pcall(cfg_mod.get)
        if ok_get and type(global_cfg) == "table" and type(global_cfg.providers) == "table" then
          for _, pc in ipairs(global_cfg.providers) do
            if pc.name == "complexity" then
              provider_config = pc
              break
            end
          end
        end
      end
    end
    local min_level = (provider_config and provider_config.min_level) or "L"
    local function_lines = utils.get_function_lines(bufnr, func_info)
    if not function_lines or #function_lines == 0 then
      debug.log_context("Complexity", "no function content found for '" .. (func_info.name or "unknown") .. "'")
      callback(nil)
      return
    end

    debug.log_context("Complexity", "analyzing " .. #function_lines .. " lines for function '" .. (func_info.name or "unknown") .. "'")
    local filetype = vim.bo[bufnr].filetype or "default"
    local complexity_label, score = estimate_complexity(function_lines, filetype)
    debug.log_context("Complexity", "complexity: " .. complexity_label .. " (score: " .. score .. ")")

    if not should_show_complexity(complexity_label, min_level) then
      debug.log_context("Complexity", "skipping - below min_level: " .. min_level)
      callback(nil)
      return
    end

    callback({
      line = func_info.line,
      text = format_complexity(complexity_label)
    })
  end
}

return provider