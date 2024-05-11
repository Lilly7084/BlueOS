local Package = {}
local loaded = {}  -- Cache of already-loaded DLLs
local loading = {}  -- Lists DLLs in flight to detect circular dependencies
--------------------------------------------------------------------------------

-- Resolve the absolute path of a library's main file from a name
Package.find = function (name)
    checkArg(1, name, "string")
    -- TODO: Support multiple library paths (i.e. /Libraries/), bundles, etc.
    return "/System/Libraries/" .. name .. ".lua"
end

-- Load in a library, not respecting the caches
local loadLib = function (name, ...)
    local step, result, reason = "not loaded", name, nil
    if result then --find
        step, result, reason = "not found", Package.find(result)
    end
    if result then --load
        step, result, reason = "load failed", loadfile(result)
    end
    if result then --init
        step, result, reason = "init failed", bpcall(result, ...)
    end
    -- If we failed at any point, compose the error message
    if not result then
        reason = tostring(reason) or "unknown error"
        return nil, "Package '"..name.."' "..step..": "..reason
    end
    return result
end

-- Load in a library, respecting the cache and catching circular dependencies
Package.require = function (name, ...)
    if Package.loaded[name] then  -- Already loaded
        return Package.loaded[name]
    elseif Package.loading[name] then  -- Circular dependency
        error("Package '"..name.."' already loading: circular dependency?")
    else  -- Not yet loaded
        Package.loading[name] = true
        local result, reason = loadLib(name, ...)
        if not result then
            error(reason)
        end
        Package.loaded[name] = result  -- Add to the cache
        Package.loading[name] = nil  -- Consumes less memory than 'false'
        return result
    end
end

-- Hook a 'delay file' to a library; the first time that any function not
-- already defined in the library is called, the delay file is executed and
-- *should* register the missing functions
Package.delay = function (lib, path)
    checkArg(1, lib, "table")
    checkArg(2, path, "string")
    local meta = {}
    meta.__index = function (tbl, key)
        meta.__index = nil  -- Remove this handler so it doesn't run twice
        dofile(path, lib)
        return tbl[key]
    end
    return setmetatable(lib, meta)
end

--------------------------------------------------------------------------------
Package.loaded = loaded
Package.loading = loading
_G.require = Package.require
return Package
