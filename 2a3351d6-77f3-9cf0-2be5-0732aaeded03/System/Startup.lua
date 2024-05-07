_G._OSVERSION = "BlueOS 0.0.1"
component.proxy = nil  -- We can't use that, remember?

--------------------------------------------------------------------------------
-- Collection of useful functions during bootstrap time (libk)

local loadfile = ...  -- Passed down from /init.lua

-- Fetch system calls now to avoid software rug-pulls
local _cInvoke = component.invoke
local _cList = component.list
local _cUptime = computer.uptime
local _cPullSignal = computer.pullSignal
local _cPushSignal = computer.pushSignal

-- Invoke a method of a component
local invoke = function (addr, method, ...)
    checkArg(1, addr, "string")
    checkArg(2, method, "string")
    local result = table.pack(xpcall(_cInvoke, function (err)
        return tostring(err) .. "\n" .. debug.traceback()
    end, addr, method, ...))
    if not result[1] then
        return nil, result[2]
    end
    return table.unpack(result, 2, result.n)
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
local cursor = 1
local lastYield = _cUptime()
local message = function (msg)
    if gpu then
        -- Scroll the screen up if the text has reached the bottom
        if cursor > height then
            invoke(gpu, "copy", 1, 2, width, height - 1, 0, -1)
            invoke(gpu, "fill", 1, height, width, 1, " ")
            cursor = height
        end
        invoke(gpu, "set", 1, cursor, tostring(msg))
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

--------------------------------------------------------------------------------

message("Hello, world!")
