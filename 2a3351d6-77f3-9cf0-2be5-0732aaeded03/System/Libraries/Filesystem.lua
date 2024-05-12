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
    local pathComp = table.concat(segments, "/") .. "/"
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
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    local list, reason = proxy.list(proxyPath)
    if not list then return nil, reason end
    -- Add in any mounted paths which exist in the same folder
    for _, mount in ipairs(mounts) do
        local pathComp, nameComp = pathAndName(mount.path)
        if pathComp == path and nameComp then
            table.insert(list, nameComp .. "/")
        end
    end
    return list
end

-- Creates a directory at the specified path
Filesystem.makeDirectory = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.makeDirectory(proxyPath)
end

-- Removes the item at the specified path. Recursively empties out folders.
Filesystem.remove = function (path)
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    -- Clear out all the items inside if this is a folder
    if proxy.isDirectory(proxyPath) then
        local list, reason = proxy.list(proxyPath)
        if not list then return nil, reason end
        for _, item in ipairs(list) do
            Filesystem.remove(Filesystem.concat(path, item))
        end
    end
    -- Do the actual deletion now
    return proxy.remove(proxyPath)
end

-- Renames a file or folder. Can copy files if the paths are on different
-- volumes, but cannot copy folders.
Filesystem.rename = function (oldPath, newPath)
    local oldProxy, oldProxyPath = Filesystem.get(oldPath)
    if not oldProxy then return nil, oldProxyPath end
    local newProxy, newProxyPath = Filesystem.get(newPath)
    if not newProxy then return nil, newProxyPath end
    -- Bail out now in case of anything that would stop us later
    if oldProxy.isDirectory(oldProxyPath) then
        return nil, "Is a directory"
    end
    if newProxy.exists(newProxyPath) then
        return nil, "Item already exists"
    end
    -- If the volumes are different, copy then delete the original
    if oldProxy.address ~= newProxy.address then
        Filesystem.copy(oldPath, newPath) -- This runs .get() again but meh
        return oldProxy.remove(oldProxyPath)
    end
    -- Otherwise it really is just renaming the file
    return oldProxy.rename(oldProxyPath, newProxyPath)
end

-- Copies a file from one location to another.
Filesystem.copy = function (fromPath, toPath)
    local from = Filesystem.open(fromPath, "r")
    local to = Filesystem.open(toPath, "w")
    local chunk, reason
    repeat
        chunk, reason = from:read()
        to:write(chunk or "")
    until not chunk or string.len(chunk) == 0
    from:close()
    to:close()
    if reason then
        return nil, reason
    end
    return true
end

--------------------------------------------------------------------------------
-- File handles

local fileRead = function (self, n)
    checkArg(1, n, "number", "nil")
    n = n or math.huge
    local buffer = ""
    repeat
        local chunk, reason = self.proxy.read(self.stream, n)
        if not chunk and reason then
            return nil, reason
        end
        buffer = buffer .. (chunk or "")
    until not chunk
    self.offset = self.offset + string.len(buffer)
    return buffer
end

local fileWrite = function (self, str)
    checkArg(1, str, "string")
    local result, reason = self.proxy.write(self.stream, str)
    if result then
        self.offset = self.offset + string.len(str)
    end
    return result, reason
end

local fileSeek = function (self, whence, offset)
    checkArg(1, whence, "string")
    checkArg(1, offset, "number", "nil")
    offset = offset or 0
    if whence == "set" then
        -- Relative to start of file
        local result, reason = self.proxy.seek(self.stream, "set", offset)
        if result then
            self.offset = result
        end
        return result, reason
    elseif whence == "cur" then
        -- Relative to current position
        local result, reason = self.proxy.seek(self.stream, "set", self.offset + offset)
        if result then
            self.offset = result
        end
        return result, reason
    elseif whence == "end" then
        -- Relative to end of file
        local result, reason = self.proxy.seek(self.stream, "end", offset)
        if result then
            self.offset = result
        end
        return result, reason
    else
        -- Invalid
        return nil, "Invalid seek mode"
    end
end

local fileClose = function (self)
    return self.proxy.close(self.stream)
end

Filesystem.open = function (path, mode)
    checkArg(1, path, "string")
    checkArg(1, mode, "string", "nil")
    mode = mode or "r"
    local proxy, proxyPath = Filesystem.get(path)
    if not proxy then return nil, proxyPath end
    local handle, reason = proxy.open(proxyPath, mode)
    if not handle then return nil, reason end
    -- Construct the file proxy
    local file = {
        proxy = proxy,
        stream = handle,
        offset = 0,
        seek = fileSeek,
        close = fileClose
    }
    -- Add in the extra methods which are specific to certain modes
    if mode == "r" or mode == "rb" then
        -- Read
        file.read = fileRead
    elseif mode == "w" or mode == "wb" or mode == "a" or mode == "ab" then
        -- Write
        file.write = fileWrite
    else
        -- Invalid
        file:close() -- Clean up
        return nil, "Invalid access mode"
    end
    return file
end

--------------------------------------------------------------------------------
Filesystem.mounts = mounts
return Filesystem
