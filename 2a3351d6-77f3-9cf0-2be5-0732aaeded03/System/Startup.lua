_G._OSVERSION = "BlueOS 0.0.1"

-- Fetch system calls now to avoid software rug-pulls
local _cInvoke = component.invoke
local _cList = component.list
local _cUptime = computer.uptime
local _cPullSignal = computer.pullSignal
local _cPushSignal = computer.pushSignal
local _dTraceback = debug.traceback

-- Useful protected call that will come up almost everywhere else
bpcall = function (func, ...)
    checkArg(1, func, "function")
    local result = table.pack(xpcall(func, function (err)
        return tostring(err) .. "\n" .. _dTraceback()
    end, ...))
    if not result[1] then
        return nil, result[2]
    end
    return table.unpack(result, 2, result.n)
end

--------------------------------------------------------------------------------
-- Initial implementations of stblib methods, good enough for the bootstrap.
-- These will be replaced and unloaded once their real implementations load in.

local invoke = function (addr, method, ...)
    checkArg(1, addr, "string")
    checkArg(2, method, "string")
    return bpcall(_cInvoke, addr, method, ...)
end

-- Prepare the graphics hardware for debug output
local screen = _cList("screen")()
local gpu = screen and _cList("gpu")()
local width, height
if gpu then
    invoke(gpu, "bind", screen)
    width, height = invoke(gpu, "maxResolution")
    invoke(gpu, "setResolution", width, height)
    invoke(gpu, "setForeground", 0xFFFFFF)
    invoke(gpu, "setBackground", 0x000000)
    invoke(gpu, "fill", 1, 1, width, height, " ")
end

-- Print a line of debug text to the screen
-- Replaced later by IO package, so this will all be unloaded
local cursor = 1
local lastYield = _cUptime()
printf = function (...)
    if gpu then
        -- Scroll the screen up if the text has reached the bottom
        if cursor > height then
            invoke(gpu, "copy", 1, 2, width, height - 1, 0, -1)
            invoke(gpu, "fill", 1, height, width, 1, " ")
            cursor = height
        end
        invoke(gpu, "set", 1, cursor, string.format(...))
        cursor = cursor + 1
    end
    -- Yield from time to time, so the watchdog timer doesn't reset us
    if _cUptime() - lastYield > 1 then
        lastYield = _cUptime()
        -- Pulling a signal (or trying to) resets the timer
        local signal = table.pack(_cPullSignal(0))
        -- If we did catch something, we now have to release it
        if signal.n > 0 then
            _cPushSignal(table.unpack(signal, 1, signal.n))
        end
    end
end

-- Needs to be public so that Package can get started.
-- Will be replaced (and then deallocated by the runtime) shortly after.
loadfile = ...  -- Passed down from /init.lua

dofile = function (path, ...)
    local func, reason = loadfile(path)
    if not func then
        return nil, reason
    end
    return bpcall(func, ...)
end

--------------------------------------------------------------------------------
-- Real initialization process

do
    printf("%s (%s) - Loading...", _OSVERSION, _VERSION)

    printf("Preloading system DLLs...")
    local Package = loadfile("/System/Libraries/Package.lua")()
    local loaded = Package.internal.loaded
    loaded.Package = Package

    -- Mark libraries which are available during bootstrap time
    loaded._G = _G
    loaded.Coroutine = coroutine
    loaded.Math = math
    loaded.String = string
    loaded.Unicode = unicode
    loaded.Utf8 = utf8
    -- Temporary (remove once actual library is added)
    loaded.Bit32 = bit32 -- Must be provided by us for Lua 5.3+
    loaded.Computer = computer
    loaded.OS = os -- Some methods must be added in software
    loaded.Table = table -- Plan to add .merge, .clone, etc.

    -- Pre-load libraries which will be needed by basically everything
    local preloadLibs = {
        "Event",
        "Component",
        "Filesystem",
    }
    for i, name in ipairs(preloadLibs) do
        printf("  (%i/%i) %s", i, #preloadLibs, name)
        require(name)
    end

    -- Flush signal queue to give everything time to initialize
    local times = require("Event").flush()
    printf("Flushed signal queue after %i loop(s)", times)

    -- Clean up global namespace
    _G.component = nil
    _G.computer = nil
    _G.debug = nil
    _G.unicode = nil
    _G.utf8 = nil
    
    printf("Initializing filesystems...")
    local Filesystem = require("Filesystem")
    Filesystem.mount(require("Component").eeprom.getData(), "/")
    Filesystem.mount(require("Computer").tmpAddress(), "/Temp/")
end

require("Shell").start()
