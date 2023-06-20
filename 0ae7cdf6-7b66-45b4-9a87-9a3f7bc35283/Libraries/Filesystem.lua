local Component = require("Component")

local filesystem = {}

local mounts = {}

local CHUNK_SIZE = 1024
local DEFAULT_LITTLE_ENDIAN = true

--------------------------------------------------------------------------------
-- Path processing

filesystem.segments = function (path, opt_parts)
    checkArg(1, path, "string")
    checkArg(2, opt_parts, "table", "nil")
    local parts = opt_parts or {}
    for part in path:gmatch("[^\\/]+") do
        local current, up = part:find("^%.?%.$")
        if current then
            if up == 2 then
                table.remove(parts)
            end
        else
            table.insert(parts, part)
        end
    end
    return parts
end

filesystem.canonical = function (path)
    checkArg(1, path, "string")
    local result = table.concat(filesystem.segments(path), "/")
    if string.sub(path, 1, 1) == "/" then
        return "/" .. result
    else
        return result
    end
end

filesystem.concat = function (...)
    local set = table.pack(...)
    for index, value in ipairs(set) do
        checkArg(index, value, "string")
    end
    return filesystem.canonical(table.concat(set, "/"))
end

filesystem.path = function (path)
    checkArg(1, path, "string")
    local parts = filesystem.segments(path)
    local result = table.concat(parts, "/", 1, #parts - 1) .. "/"
    if string.sub(path, 1, 1) == "/" and string.sub(result, 1, 1) ~= "/" then
        return "/" .. result
    else
        return result
    end
end

filesystem.name = function (path)
    checkArg(1, path, "string")
    local parts = filesystem.segments(path)
    return parts[#parts]
end

--------------------------------------------------------------------------------
-- Mount management

filesystem.mount = function (proxy, path)
    checkArg(1, proxy, "table")
    checkArg(2, path, "string")
    -- Make sure filesystem and path are both available
    for _, mount in ipairs(mounts) do
        if mount.path == path then
            return false, "Mount path already in use"
        elseif mount.proxy == proxy then
            return false, "Proxy already mounted"
        end
    end
    -- Mount proxy now
    table.insert(mounts, {
        path = path,
        proxy = proxy
    })
    -- Sort mount table, putting MORE SPECIFIC mount points first,
    -- to make filesystem.get()'s job easier
    table.sort(mounts, function(a, b)
        return #a.path > #b.path
    end)
    return true
end

filesystem.unmount = function (fsOrPath)
    checkArg(1, fsOrPath, "table", "string")
    if type(fsOrPath) == "table" then
        -- Proxy
        for index, mount in ipairs(mounts) do
            if mount.proxy == fsOrPath then
                table.remove(mounts, index)
                return true
            end
        end
        return false, "Specified proxy is not mounted"
    else
        -- Path
        for index, mount in ipairs(mounts) do
            if mount.path == fsOrPath then
                table.remove(mounts, index)
                return true
            end
        end
        return false, "Specified path is not mounted"
    end
end

filesystem.mounts = function ()
    local key, value
    return function ()
        key, value = next(mounts, key)
        if value then
            return value.proxy, value.path
        end
    end
end

filesystem.proxy = function (filter)
    checkArg(1, filter, "string")
    -- Try via full or partial address
    local addr, proxy = component.get(filter)
    if addr then
        return proxy
    end
    -- Try via filesystem label
    for c in component.list("filesystem", true) do
        local _, proxy = component.get(addr)
        if proxy.getLabel() == filter then
            return proxy
        end
    end
    -- Failed
    return nil, "No such filesystem"
end

filesystem.get = function (path)
    checkArg(1, path, "string")
    for _, mount in ipairs(mounts) do
        if path:sub(1, string.len(mount.path)) == mount.path then
            return mount.proxy, path:sub(mount.path:len() + 1, -1)
        end
    end
    return nil, "No such path"
end

--------------------------------------------------------------------------------
-- Forwarded proxy methods

filesystem.exists = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.exists(proxyPath)
end

filesystem.size = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.size(proxyPath)
end

filesystem.isDirectory = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.isDirectory(proxyPath)
end

filesystem.lastModified = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.lastModified(proxyPath)
end

filesystem.list = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    local data = proxy.list(proxyPath)
    local key, value
    return function ()
        key, value = next(data, key)
        if value then
            return value
        end
    end
end

filesystem.makeDirectory = function (path)
    local proxy, proxyPath = filesystem.get(path)
    if not proxy then return nil, proxyPath end
    return proxy.makeDirectory(proxyPath)
end

--------------------------------------------------------------------------------
-- File move

filesystem.remove = function (path)
    local success = false
    for _, mount in ipairs(mounts) do
        if mount.path:sub(1, string.len(path)) == path then
            local proxyPath = mount.path:sub(path:len() + 1, -1)
            mount.proxy.remove(proxyPath)
            success = true
        end
    end
    return false
end

filesystem.move = function (fromPath, toPath)
    local fromProxy, fromProxyPath = component.get(fromPath)
    local toProxy, toProxyPath = component.get(toPath)
    -- Try for a same-drive move
    if fromProxy == toProxy then
        return fromProxy.rename(fromProxyPath, toProxyPath)
    end
    -- Different drives: Copy file over and remove original
    if filesystem.copy(fromPath, toPath) then
        return filesystem.remove(fromPath)
    end
    return false -- TODO: May leave garbage on the destination drive
end

filesystem.copy = function (fromPath, toPath)
    -- TODO: Can't copy files, since we need to be able to read them
    return false
end

--------------------------------------------------------------------------------
-- File read/write methods

local fileSeek = function (self, whence, offset)
    if whence ~= "set" and whence ~= "cur" and whence ~= "end" then
        error("bad argument #2 ('set', 'cur' or 'end' expected, got " ..
            tostring(whence) .. ")")
    end
    checkArg(2, offset, "number", "nil")
    local result, reason = self.proxy.seek(self.handle, whence, offset)
    if result then
        self.position = result
        self.buffer = ""
    end
    return result, reason
end

local fileClose = function (self)
    -- Flush buffer for writing files
    if self.write and #self.buffer > 0 then
        self.proxy.write(self.handle, self.buffer)
    end
    return self.proxy.close(self.handle)
end

local fileReadString = function (self, count)
    checkArg(1, count, "number")
    -- Return from buffer, if possible
    if count <= #self.buffer then
        local data = self.buffer:sub(1, count)
        self.buffer = self.buffer:sub(count + 1, -1)
        self.position = self.position + count
        return data
    end
    -- Read enough data to fill the requested string
    local data = self.buffer
    while #data < count do
        local chunk = self.proxy.read(self.handle, CHUNK_SIZE)
        data = data .. (chunk or "")
        -- Prematurely reached end of file
        if not chunk then
            self.position = fileSeek(self, "end", 0)
            return #data > 0 and data or nil
        end
    end
    -- Update buffer to contain unused read data
    self.buffer = data:sub(count + 1, -1)
    data = data:sub(1, count)
    self.position = self.position + #data
    return data
end

local fileReadLine = function (self)
    local data = ""
    while true do
        -- Exhaust buffer immediately
        if #self.buffer > 0 then
            local starting, ending = self.buffer:find("\n")
            if starting then
                local chunk = self.buffer:sub(1, starting - 1)
                self.buffer = self.buffer:sub(ending + 1, -1)
                self.position = self.position + #chunk
                return data .. chunk
            else
                data = data .. self.buffer
            end
        end
        -- Refill buffer
        local chunk = self.proxy.read(self.handle, CHUNK_SIZE)
        if chunk then
            self.buffer = chunk
            self.position = self.position + #chunk
        else
            -- Hit end of file
            local data = self.buffer
            self.position = fileSeek(self, "end", 0)
            return #data > 0 and data or nil
        end
    end
end

local fileIterLines = function (self)
    return function ()
        local line = fileReadLine(self)
        if line then
            return line
        end
        fileClose(self)
    end
end

local fileReadAll = function (self)
    local data = ""
    while true do
        local chunk = self.proxy.read(self.handle, CHUNK_SIZE)
        if chunk then
            data = data .. chunk
        else
            -- Hit end of file
            self.position = fileSeek(self, "end", 0)
            return data
        end
    end
end

local fileReadBytes = function (self, count, littleEndian)
    checkArg(1, count, "number")
    checkArg(2, littleEndian, "boolean", "nil")
    if littleEndian == nil then
        littleEndian = DEFAULT_LITTLE_ENDIAN
    end
    -- Read single byte
    if count == 1 then
        local data = fileReadString(self, 1)
        if data then
            return string.byte(data)
        end
        return nil
    end
    -- Read multiple bytes
    local bytes = {string.byte(fileReadString(self, count) or "\x00", 1, 0)}
    -- Endianness settings
    local starting = littleEndian and #bytes or 1
    local ending   = littleEndian and 1      or #bytes
    local step     = littleEndian and -1     or 1
    -- Rearrange into number
    local result = 0
    for i = starting, ending, step do
        result = bit32.bor(bit32.lshift(result, 8), bytes[i])
    end
    return result
end

local fileReadFormatted = function (self, format, ...)
    checkArg(1, format, "string", "number", "nil")
    -- read() -> Read everything
    if type(format) == "nil" then
        return fileReadAll(self)
    end
    -- read(int) -> Read specified number of chars
    if type(format) == "number" then
        return fileReadString(self, format)
    end
    -- read(fmt, ...) -> Read formatted data
    local counts = table.pack(...)
    for index, value in ipairs(counts) do
        checkArg(index + 1, value, "number")
    end
    local countIndex = 1
    local result = {}
    for i = 1, #format do
        local c = format:sub(i, i)
        if c == "a" then
            table.insert(result, fileReadAll(self))
            break
        elseif c == "l" then
            table.insert(result, fileReadLine(self))
        elseif c == "s" then
            local count = counts[countIndex]
            countIndex = countIndex + 1
            table.insert(result, fileReadString(self, count))
        elseif c == "b" then
            local count = counts[countIndex]
            countIndex = countIndex + 1
            table.insert(result, fileReadBytes(self, count))
        end
        -- TODO: Binary data formats?
    end
    return result
end

local fileWriteString = function (self, data)
    checkArg(1, data, "string")
    -- Small enough to fit in buffer:
    if #data < (CHUNK_SIZE - #self.buffer) then
        self.buffer = self.buffer .. data
        return true
    end
    -- Write out current contents of buffer
    local success, reason = self.proxy.write(self.handle, self.buffer)
    if not success then
        return false, reason
    end
    -- Small enough to fit in buffer:
    if #data <= CHUNK_SIZE then
        self.buffer = data
        return true
    end
    -- Write out in pieces
    for i = 1, #data, CHUNK_SIZE do
        success, reason = self.proxy.write(self.handle,
            string.sub(data, i, i + CHUNK_SIZE - 1))
        if not success then
            break
        end
    end
    self.buffer = ""
    return success, reason
end

--------------------------------------------------------------------------------
-- File manipulation

filesystem.open = function (path, mode)
    local proxy, proxyPath = filesystem.get(path)
    local handle, reason = proxy.open(proxyPath, mode)
    if not handle then
        return nil, reason
    end
    -- Common members
    local file = {
        proxy = proxy,
        handle = handle,
        position = 0,
        buffer = "",
        close = fileClose,
        seek = fileSeek
    }
    -- Reading members
    if mode == "r" or mode == "rb" then
        file.readString = fileReadString
        file.readBytes = fileReadBytes
        file.readLine = fileReadLine
        file.lines = fileIterLines
        file.readAll = fileReadAll
        file.read = fileReadFormatted
        return file
    -- Writing members
    elseif mode == "w" or mode == "wb" or mode == "a" or mode == "ab" then
        file.write = fileWriteString
        return file
    -- Unsupported mode
    else
        error("bad argument #2 ('r', 'rb', 'w', 'wb' or 'a' expected, got )" ..
            tostring(mode) .. ")")
    end
end

--------------------------------------------------------------------------------
-- Reimplement loadfile and dofile to use newly loaded driver

loadfile = function (path)
    checkArg(1, path, "string")
    local file, reason = filesystem.open(path, "r")
    if not file then
        return nil, reason
    end
    local data = file:readAll()
    file:close()
    return load(data, "=" .. path)
end

dofile = function (path, ...)
    local code, reason = loadfile(path)
    if not code then
        error(reason)
    end
    local data = table.pack(xpcall(code, debug.traceback, ...))
    if not data[1] then
        error(data[2])
    end
    return table.unpack(data, 2, data.n)
end

--------------------------------------------------------------------------------
-- Automatically mount and unmount filesystems

-- Required filesystems (main and temp)
local fs = component.proxy(computer.getBootAddress())
if not filesystem.mount(fs, "/") then -- bootfs
    error("Failed to mount main filesystem!")
end
fs = component.proxy(computer.tmpAddress())
if not filesystem.mount(fs, "/Temp/") then -- tmpfs
    error("Failed to mount temporary filesystem!")
end

-- TODO: Handle removable filesystems

--------------------------------------------------------------------------------

return filesystem
