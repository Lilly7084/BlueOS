local Filesystem = {}
local mounts = {}

local Component = require("Component")
--------------------------------------------------------------------------------
-- Path string manipulation

-- Returns the canonical segments of a path string
Filesystem.segments = function (path, isFirst)
    checkArg(1, path, "string")
    checkArg(2, isFirst, "boolean", "nil")
    local segments, absolute = {}, false
    if isFirst then
        absolute = string.sub(path, 1, 1) == "/"
    end
    for segment in string.gmatch(path, "([^/]+)") do
        if segment == "" then -- Reset to filesystem root
            segments = {}
            absolute = true
        elseif segment == ".." then -- Parent node
            table.remove(segments, #segments)
        else -- Child node
            table.insert(segments, segment)
        end
    end
    return segments, absolute
end

-- Returns the canonical form of a path string (joined by single slashes)
Filesystem.canonical = function (path)
    local segments, absolute = Filesystem.segments(path, true)
    return (absolute == "/" and "/" or "") .. table.concat(segments, "/")
end

-- Concatenate multiple path strings
Filesystem.concat = function (...)
    local paths = {...}
    local current = ""
    for i, path in ipairs(paths) do
        checkArg(i, path, "string")
        if i > 1 and string.sub(path, 1, 1) == "/" then
            path = string.sub(path, 2)
        end
        if string.sub(path, #path, #path) == "/" then
            path = string.sub(path, 1, #path - 1)
        end
        current = current .. "/" .. path
    end
    return Filesystem.canonical(current)
end

-- Split a path string into the path and name components
local pathAndName = function (path)
    local segments, absolute = Filesystem.segments(path)
    local nameComp = segments[#segments]
    table.remove(segments, #segments)
    local pathComp = table.concat(segments, "/")
    return pathComp, nameComp
end

-- Get the path component (leading up to the last slash) of a path string
Filesystem.path = function (path)
    local pathComp, _ = pathAndName(path)
    return pathComp
end

-- Get the name component (after the last slash) of a path string
Filesystem.name = function (path)
    local _, nameComp = pathAndName(path)
    return nameComp
end

--------------------------------------------------------------------------------
-- Mounted volumes

-- Retrieve the proxy of a filesystem component from its address or label
Filesystem.proxy = function (volume)
    checkArg(1, volume, "string")
    -- Try it as an address first
    local resolve, _ = Component.get(volume, "filesystem")
    if resolve then
        return Component.proxy(resolve)
    end
    -- Now search through all filesystems to find one with the right label
    for addr, _ in Component.list("filesystem") do
        if Component.invoke(addr, "getLabel") == volume then
            return Component.proxy(addr)
        end
    end
    -- We failed
    return nil, "No such volume"
end

-- Mount a volume (specified by proxy, address, or label) at a specific path
Filesystem.mount = function (volume, path)
    checkArg(1, volume, "string", "table")
    checkArg(2, path, "string")
    -- Make sure that 'volume' is a filesystem proxy
    if type(volume) == "string" then
        volume = Filesystem.proxy(volume)
    elseif volume.type ~= "filesystem" then
        return nil, "Incorrect proxy type"
    end
    -- Make sure the proxy and mount point aren't already in use
    for _, mount in ipairs(mounts) do
        if mount.proxy.address == volume.address then
            return nil, "Volume already mounted"
        end
        -- TODO: Let an existing folder prevent a mount?
        if mount.path == path then
            return nil, "Item already exists"
        end
    end
    -- Now actually do the mount
    table.insert(mounts, { proxy = volume, path = path })
    -- Sort the table so that longer mount names appear first
    table.sort(mounts, function(a, b) return #b.path < #a.path end)
    return true
end

-- Unmount a volume, specified by proxy, address, label, or mount path
Filesystem.unmount = function (volume)
    checkArg(1, volume, "string", "table")
    if type(volume) == "string" then
        -- Try as a mount path first
        for id, mount in ipairs(mounts) do
            if mount.address == volume then
                mounts[id] = nil
                return true
            end
        end
        -- That failed, so the string must be an address or label
        volume = Filesystem.proxy(volume)
    elseif volume.type ~= "filesystem" then
        return nil, "Incorrect proxy type"
    end
    -- Now unmount based on proxy
    for id, mount in ipairs(mounts) do
        if mount.proxy.address == volume.address then
            mounts[id] = nil
            return true
        end
    end
    -- We failed
    return nil, "No such volume"
end

-- Get the volume proxy and volume-relative path for a given absolute path
Filesystem.get = function (path)
    checkArg(1, path, "string")
    for _, mount in ipairs(mounts) do
        local len = string.len(mount.path)
        if string.sub(path, 1, len) == mount.path then
            return mount.proxy, string.sub(path, len + 1)
        end
    end
    -- We failed
    return nil, "Path not found"
end

--------------------------------------------------------------------------------
-- Filesystem controls, forwarded to relevant volumes

-- Returns whether a file or folder exists at the specified path
Filesystem.exists = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.exists(proxyPath)
end

-- Returns the size of a file at the specified path, or 0 for folders
Filesystem.size = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.size(proxyPath)
end

-- Returns whether a folder (not a file) exists at the specified path
Filesystem.isDirectory = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.isDirectory(proxyPath)
end

-- Returns the real world Unix time stamp of a file's mtime (or folder's ctime)
Filesystem.lastModified = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.lastModified(proxyPath)
end

-- Returns an iterator over all the items in the directory at a path
Filesystem.list = function (path)
    error("Filesystem.list() not yet implemented!")
end

-- Creates a directory at the specified path
Filesystem.makeDirectory = function (path)
    error("Filesystem.makeDirectory() not yet implemented!")
end

-- Removes the item at the specified path. Recursively empties out folders.
Filesystem.remove = function (path)
    error("Filesystem.remove() not yet implemented!")
end

-- Renames a file or folder. Can copy files if the paths are on different
-- volumes, but cannot copy folders.
Filesystem.rename = function (oldPath, newPath)
    error("Filesystem.rename() not yet implemented!")
end

-- Copies a file from one location to another.
Filesystem.copy = function (fromPath, toPath)
    error("Filesystem.copy() not yet implemented!")
end

--------------------------------------------------------------------------------
-- File handles (TODO)

Filesystem.open = function (path, mode)
    error("Filesystem.open() not yet implemented!")
end

--------------------------------------------------------------------------------
Filesystem.mounts = {}
return Filesystem
