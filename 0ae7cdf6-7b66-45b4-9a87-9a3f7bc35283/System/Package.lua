local bootFS = component.proxy(computer.getBootAddress())

local package = {
    paths = { "/Libraries/" },
    loaded = {}, -- Package returns OR TRUE for everything that's loaded
    loading = {}, -- Note packages being loaded to catch circular dependencies
    exists = bootFS.exists
}

local titleCase = function (str)
    return str:sub(1, 1):upper() .. str:sub(2)
end

-- Try to find the actual path for a library
local findPackageFile = function (name)
    checkArg(1, name, "string")
    local cases = {
        string.lower,
        titleCase
    }
    -- List of files that could be what we want
    local variants = {}
    for _, path in ipairs(package.paths) do
        for _, case in ipairs(cases) do
            local filename = case(name)
            table.insert(variants, path .. filename .. ".lua")
        end
    end
    -- Run through the list until we find one that exists
    for _, variant in ipairs(variants) do
        if package.exists(variant) then
            return variant
        end
    end
    -- We failed
    error("Could not find suitable file for library \"" .. name .. "\"")
end

require = function (name)
    -- TODO: Module IDs may need to be reformatted
    local id = unicode.lower(name)
    if package.loaded[id] then
        return package.loaded[id]
    elseif package.loading[id] then
        error("Found circular dependency in library \"" .. name .. "\"")
    else
        -- Load the library, since it's not already loaded
        package.loading[id] = true
        local path = findPackageFile(name)
        local result = dofile(path)
        package.loaded[id] = result or true
        package.loading[id] = nil
        return result
    end
end


return package
