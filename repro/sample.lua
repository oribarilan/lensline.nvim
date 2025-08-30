-- Sample Lua file for lensline bug reproduction
-- This file contains functions with different reference counts for testing

-- Function with no references (0 refs)
local function unused_function()
    return "This function is never called"
end

-- Function with some references (2 refs)
local function helper_function(x, y)
    return x + y
end

-- Function with multiple references (3 refs)
local function popular_function(data)
    if not data then
        return nil
    end
    return data.value or "default"
end

-- Usage to create references
local result1 = helper_function(1, 2)
local result2 = helper_function(3, 4)

local value1 = popular_function({value = "test"})
local value2 = popular_function(nil)
local value3 = popular_function({other = "field"})

-- Main function
local function main()
    print("Sample Lua file loaded")
    print("Result:", result1, result2)
    print("Values:", value1, value2, value3)
end

return {
    main = main,
    helper = helper_function,
    popular = popular_function
}