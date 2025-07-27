local utils = require("lensline.utils")

-- Helper function to format time as natural relative text (1h ago, 2d ago, etc.)
local function format_relative_time(timestamp)
  local now = os.time()
  local diff = now - timestamp
  
  -- Less than 1 hour -> 1h ago
  if diff < 3600 then
    return "1h ago"
  end
  
  -- 1-23 hours -> Xh ago (rounded)
  if diff < 86400 then -- 24 hours
    local hours = math.floor(diff / 3600)
    return hours .. "h ago"
  end
  
  -- 1-364 days -> Xd ago (rounded)
  if diff < 31536000 then -- 365 days
    local days = math.floor(diff / 86400)
    return days .. "d ago"
  end
  
  -- 1+ years -> Xy ago (rounded)
  local years = math.floor(diff / 31536000)
  return years .. "y ago"
end

-- Helper function to parse git blame --line-porcelain output to find the latest author
local function parse_blame_output(blame_output, debug)
  local latest_author, latest_time = nil, 0
  local current_author, current_time = nil, nil
  
  debug.log_context("LastAuthor", "parsing " .. #blame_output .. " lines of blame output")
  
  for _, line in ipairs(blame_output) do
    -- Extract author name
    local author = line:match("^author (.+)$")
    if author then
      current_author = author
    end
    
    -- Extract author timestamp
    local time_str = line:match("^author%-time (%d+)$")
    if time_str then
      current_time = tonumber(time_str)
      
      -- Check if this is the latest author so far
      if current_author and current_time and current_time > latest_time then
        latest_author = current_author
        latest_time = current_time
        debug.log_context("LastAuthor", "new latest author: " .. latest_author .. " at " .. latest_time)
      end
    end
  end
  
  if latest_author and latest_time > 0 then
    local relative_time = format_relative_time(latest_time)
    local result = latest_author .. " (" .. relative_time .. ")"
    debug.log_context("LastAuthor", "final result: " .. result)
    return "󰊢 " .. result
  else
    debug.log_context("LastAuthor", "no valid author/time found in blame output")
    return nil
  end
end

-- Helper function to get last author for a function synchronously
local function get_function_last_author_sync(filename, git_root, func, debug)
  local function_start = func.line
  local function_end = func.end_line or func.line
  local lines_range = ("%d,%d"):format(function_start, function_end)
  
  debug.log_context("LastAuthor", "sync blame request for lines " .. lines_range)
  
  local blame_cmd = { "git", "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename }
  local blame_output = vim.fn.systemlist(blame_cmd)
  
  if vim.v.shell_error ~= 0 then
    debug.log_context("LastAuthor", "git blame command failed: " .. vim.v.shell_error)
    return nil
  end
  
  return parse_blame_output(blame_output, debug)
end

-- Helper function to get last author for a function asynchronously
local function get_function_last_author_async(filename, git_root, func, callback, debug)
  local function_start = func.line
  local function_end = func.end_line or func.line
  local lines_range = ("%d,%d"):format(function_start, function_end)
  
  debug.log_context("LastAuthor", "async blame request for lines " .. lines_range)
  
  local uv = vim.loop
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local blame_output = {}
  local error_output = {}
  
  local handle
  handle = uv.spawn("git", {
    args = { "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename },
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    handle:close()
    
    vim.schedule(function()
      if code ~= 0 then
        debug.log_context("LastAuthor", "git blame failed with code " .. code .. ": " .. table.concat(error_output, " "))
        callback(nil)
        return
      end
      
      local author_info = parse_blame_output(blame_output, debug)
      callback(author_info)
    end)
  end)
  
  if not handle then
    debug.log_context("LastAuthor", "failed to spawn git blame process")
    callback(nil)
    return
  end
  
  uv.read_start(stdout, function(_, data)
    if data then
      for line in data:gmatch("[^\r\n]+") do
        table.insert(blame_output, line)
      end
    end
  end)
  
  uv.read_start(stderr, function(_, data)
    if data then
      for line in data:gmatch("[^\r\n]+") do
        table.insert(error_output, line)
      end
    end
  end)
end

-- Last Author Provider
-- Shows the most recent Git author and date for functions/methods
return {
  name = "last_author",
  event = { "BufRead", "BufWritePost" },
  debounce = 500,
  handler = function(bufnr, start_line, end_line, callback)
    local debug = require("lensline.debug")
    
    debug.log_context("LastAuthor", "handler called for buffer " .. bufnr .. " range " .. start_line .. "-" .. end_line)
    
    -- Get the file path and validate it
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" or not vim.loop.fs_stat(filename) then
      debug.log_context("LastAuthor", "invalid or unsaved file: " .. (filename or "empty"))
      if callback then callback({}) end
      return {}
    end
    
    debug.log_context("LastAuthor", "processing file: " .. filename)
    
    -- Check if we're in a git repository
    local file_dir = vim.fn.fnamemodify(filename, ":h")
    local git_root_cmd = { "git", "-C", file_dir, "rev-parse", "--show-toplevel" }
    local git_root_result = vim.fn.systemlist(git_root_cmd)
    local git_root = git_root_result[1]
    
    if vim.v.shell_error ~= 0 or not git_root or git_root == "" then
      debug.log_context("LastAuthor", "not in git repository or git command failed")
      if callback then callback({}) end
      return {}
    end
    
    debug.log_context("LastAuthor", "git root: " .. git_root)
    
    -- Find functions in the range using utility function
    local functions = utils.find_functions_in_range(bufnr, start_line, end_line)
    debug.log_context("LastAuthor", "found " .. (functions and #functions or 0) .. " functions")
    
    if not functions or #functions == 0 then
      debug.log_context("LastAuthor", "no functions found in range")
      if callback then callback({}) end
      return {}
    end
    
    local lens_items = {}
    local pending_requests = #functions
    
    -- If no callback provided, fall back to synchronous mode (for compatibility)
    if not callback then
      debug.log_context("LastAuthor", "running in synchronous mode")
      for _, func in ipairs(functions) do
        local author_info = get_function_last_author_sync(filename, git_root, func, debug)
        if author_info then
          table.insert(lens_items, {
            line = func.line,
            text = author_info
          })
        end
      end
      return lens_items
    end
    
    -- Async mode with callback
    debug.log_context("LastAuthor", "running in async mode for " .. #functions .. " functions")
    local completed = false
    
    -- Timeout safety net
    vim.defer_fn(function()
      if not completed then
        completed = true
        debug.log_context("LastAuthor", "async requests timed out after 5 seconds, calling callback with " .. #lens_items .. " items")
        callback(lens_items)
      end
    end, 5000)
    
    for _, func in ipairs(functions) do
      debug.log_context("LastAuthor", "processing function '" .. (func.name or "unknown") .. "' at line " .. func.line)
      
      get_function_last_author_async(filename, git_root, func, function(author_info)
        if completed then
          return -- Already timed out
        end
        
        if author_info then
          debug.log_context("LastAuthor", "got author info for " .. (func.name or "unknown") .. ": " .. author_info)
          table.insert(lens_items, {
            line = func.line,
            text = author_info
          })
        else
          debug.log_context("LastAuthor", "no author info for " .. (func.name or "unknown"))
        end
        
        pending_requests = pending_requests - 1
        if pending_requests == 0 and not completed then
          completed = true
          debug.log_context("LastAuthor", "all async requests completed, calling callback with " .. #lens_items .. " items")
          callback(lens_items)
        end
      end, debug)
    end
    
    -- Return empty initially for async mode
    return {}
  end
}