-- git last author collector
-- shows the last author and time since last edit for functions

-- helper function to format relative time
local function format_relative_time(timestamp)
    local current_time = os.time()
    local diff = current_time - timestamp
    
    if diff < 60 then
        return "now"
    elseif diff < 3600 then
        local minutes = math.floor(diff / 60)
        return minutes .. "m ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. "h ago"
    elseif diff < 2592000 then -- 30 days
        local days = math.floor(diff / 86400)
        return days .. "d ago"
    elseif diff < 31536000 then -- 365 days
        local months = math.floor(diff / 2592000)
        return months .. "mo ago"
    else
        local years = math.floor(diff / 31536000)
        return years .. "y ago"
    end
end

-- helper function to get current git user name
local function get_current_git_user()
    local handle = io.popen("git config user.name 2>/dev/null")
    if not handle then
        return nil
    end
    
    local user_name = handle:read("*l")
    handle:close()
    
    -- trim whitespace and return
    if user_name and user_name ~= "" then
        return user_name:match("^%s*(.-)%s*$")
    end
    
    return nil
end

-- helper function to get git blame for a specific line
local function get_git_blame(file_path, line_number)
    local cmd = string.format("git blame -L %d,%d --porcelain %s", line_number, line_number, vim.fn.shellescape(file_path))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local output = handle:read("*a")
    handle:close()
    
    if not output or output == "" then
        return nil
    end
    
    local lines = vim.split(output, "\n")
    local commit_hash = nil
    local author = nil
    local timestamp = nil
    
    for _, line in ipairs(lines) do
        if not commit_hash and line:match("^[0-9a-f]+") then
            commit_hash = line:match("^([0-9a-f]+)")
        elseif line:match("^author ") then
            author = line:match("^author (.+)")
        elseif line:match("^author%-time ") then
            timestamp = tonumber(line:match("^author%-time (%d+)"))
        end
    end
    
    if commit_hash and author and timestamp then
        return {
            commit = commit_hash,
            author = author,
            timestamp = timestamp
        }
    end
    
    return nil
end

-- helper function to check if we're in a git repository
local function is_git_repo(file_path)
    local dir = vim.fn.fnamemodify(file_path, ":h")
    local cmd = "cd " .. vim.fn.shellescape(dir) .. " && git rev-parse --is-inside-work-tree 2>/dev/null"
    local handle = io.popen(cmd)
    if not handle then
        return false
    end
    
    local result = handle:read("*l")
    handle:close()
    
    return result == "true"
end

-- helper function to get the line number for the start of a function
local function get_function_start_line(function_info)
    -- Use the function's line (1-based) directly
    return function_info.line
end

return function(git_context, function_info)
    local file_path = git_context.file_path
    
    -- check if file exists and is in a git repository
    if not file_path or file_path == "" then
        return nil, nil
    end
    
    if not vim.fn.filereadable(file_path) then
        return nil, nil
    end
    
    if not is_git_repo(file_path) then
        return nil, nil
    end
    
    local function_line = get_function_start_line(function_info)
    local cache_key = file_path .. ":" .. function_line
    
    -- check cache first
    local cached_data = git_context.cache_get(cache_key)
    if cached_data then
        return "%s", cached_data
    end
    
    -- get git blame information
    local blame_info = get_git_blame(file_path, function_line)
    if not blame_info then
        return nil, nil
    end
    
    -- check if this is an uncommitted change
    if blame_info.author == "Not Committed Yet" then
        local current_user = get_current_git_user()
        if current_user then
            local result = current_user .. ", uncommitted"
            -- don't cache uncommitted changes since they change frequently
            return "%s", result
        else
            -- fallback if we can't get current user
            local result = "uncommitted"
            return "%s", result
        end
    end
    
    -- format the output for committed changes
    local author_name = blame_info.author
    -- simplify author name if it's an email
    if author_name:match("<.+>") then
        local name_part = author_name:match("^(.-)%s*<")
        if name_part and name_part ~= "" then
            author_name = name_part
        else
            -- extract just the username from email
            local email = author_name:match("<(.+)>")
            if email then
                author_name = email:match("([^@]+)")
            end
        end
    end
    
    local relative_time = format_relative_time(blame_info.timestamp)
    local result = author_name .. ", " .. relative_time
    
    -- cache the result for committed changes
    git_context.cache_set(cache_key, result)
    
    return "%s", result
end