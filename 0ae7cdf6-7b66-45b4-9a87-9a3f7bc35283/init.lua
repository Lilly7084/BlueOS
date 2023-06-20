-- Make a panic function that stalls execution indefinitely.
-- It's its own function so that it can be replaced or intercepted,
-- in case the OS wants to handle serious errors more gracefully.
-- Note: error() is general purpose, but panic() is for fatal problems.
local _pullSignal = computer.pullSignal
panic = function (...)
    while true do
        _pullSignal()
    end
end

-- Move the boot process into its own namespace to keep _G clean
local shellPath
do
    -- Manipulate a component with automatic error handling
    local _invoke = component.invoke -- Component will be hidden later!
    local invoke = function (addr, fn, ...)
        checkArg(1, addr, "string")
        checkArg(2, fn, "string")
        local response = table.pack(pcall(_invoke, addr, fn, ...))
        if not response[1] then
            panic("invoke(): " .. response[2])
        end
        return table.unpack(response, 2, response.n)
    end

    -- Make sure the boot address can be accessed
    local eeprom = component.list("eeprom")()
    if not eeprom then
        panic("Failed to find a readable EEPROM!")
    end
    computer.getBootAddress = function ()
        return invoke(eeprom, "getData")
    end
    computer.setBootAddress = function (addr)
        checkArg(1, addr, "string")
        return invoke(eeprom, "setData", addr)
    end

    -- Temporary loadfile, since the FS driver isn't loaded yet
    local bootFS = computer.getBootAddress()
    loadfile = function (path)
        checkArg(1, path, "string")
        local CHUNK_SIZE = 1024
        local handle = invoke(bootFS, "open", path, "r")
        local data = ""
        repeat
            local chunk = invoke(bootFS, "read", handle, CHUNK_SIZE)
            data = data .. (chunk or "")
        until not chunk
        invoke(bootFS, "close", handle)
        local code, err = load(data, "=" .. path, "bt", _G)
        if not code then
            panic(err)
        end
        return code
    end

    -- Temporary dofile, since the FS driver isn't loaded yet
    dofile = function (path, ...)
        local fn = loadfile(path)
        local response = table.pack(pcall(fn, ...))
        if not response[1] then
            panic(response[2])
        end
        return table.unpack(response, 2, response.n)
    end

    -- Run the setup file
    shellPath = dofile("/System/Setup.lua", invoke)
end

xpcall(loadfile(shellPath), panic)

panic("Out of instructions!")
