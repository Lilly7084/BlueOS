local Event = {}
Event.handlers = {}

local _cUptime = computer.uptime
local _cPullSignal = computer.pullSignal
local _infinity = math.maxinteger or math.huge

-- key: nil (catch all listener), false (timer), or string (filtered listener)
-- callback: function called with unpacked signal
-- timout: max time (s) elapsed between dispatches
-- times: max number of times register can be dispatched
Event.register = function (handler)
    handler.timeout = handler.timeout or _infinity
    handler.times = handler.times or _infinity
    handler.deadline = _cUptime() + handler.timeout
    -- Find first open slot
    local id = 0
    repeat
        id = id + 1
    until not Event.handlers[id]
    -- Register in that slot
    Event.handlers[id] = handler
    return id
end

-- Cancel a handler according to the ID returned by Event.register
Event.cancel = function (id)
    checkArg(1, id, "number")
    if Event.handlers[id] then
        Event.handlers[id] = nil
        return true
    end
    return nil, "No such handler"
end

local printSignal = function (signal)
    local text = {}
    for i, chunk in ipairs(signal) do
        text[i] = tostring(chunk)
    end
    print("[Event] " .. table.concat(text, " "))
end

-- Dispatch all available handlers according to a packed signal
local dispatchSignal = function (signal)
    printSignal(signal)
    -- Create a temp. copy of Event.handlers so we can edit it while iterating
    local handlers = {}
    for k, v in ipairs(Event.handlers) do
        handlers[k] = v
    end
    for id, handler in ipairs(handlers) do
        -- key == nil => Catch-all. Timers are false so they aren't run here.
        -- key == signal[1] => Key matches first value of signal (signal ID)
        -- deadline => Deadline has been reached, handler must be run
        if handler.key == nil or handler.key == signal[1] or _cUptime() >= handler.deadline then
            handler.times = handler.times - 1
            handler.deadline = handler.deadline + handler.timeout
            -- If the handler has expired, remove it before dispatching it
            -- in case of, for example, timers that pull
            -- 'Event.handlers[id] == handler' was cargo culted from OpenOS
            if handler.times <= 0 and Event.handlers[id] == handler then
                Event.handlers[id] = nil
            end
            -- Now dispatch
            -- TODO: Report and/or log errors which occur in event handlers
            local response = bpcall(handler.callback, table.unpack(signal, 1, signal.n))
            -- A response of false (NOT nil) means the handler should be destroyed
            if response == false and Event.handlers[id] == handler then
                Event.handlers[id] = nil
            end
        end
    end
end

-- Hooked version of computer.pullSignal() that considers handlers
local hookedPull = function (timeout)
    local deadline = _cUptime() + (timeout or _infinity)
    repeat
        -- Find the deadline of the nearest handler
        local nearest = deadline
        for _, handler in ipairs(Event.handlers) do
            nearest = math.min(nearest, handler.deadline)
        end
        -- Actual pull, timing out before that deadline, so the handler is respected
        local signal = table.pack(_cPullSignal(nearest - _cUptime()))
        dispatchSignal(signal)  -- Feed it to all the handlers
        -- If we caught something, return it now; that's why we were called, after all
        if signal.n > 0 then
            return table.unpack(signal, 1, signal.n)
        end
    until _cUptime() >= deadline
    return nil
end

-- Register a listener
Event.listen = function (key, callback)
    return Event.register {
        key = key,
        callback = callback,
        timeout = _infinity,
        times = _infinity
    }
end

-- Cancel a listener based on key and callback, so you don't need the ID
Event.ignore = function (key, callback)
    checkArg(1, key, "string", "nil")
    checkArg(2, callback, "function")
    for id, handler in ipairs(Event.handlers) do
        if handler.key == key and handler.callback == callback then
            Event.handlers[id] = nil
            return true
        end
    end
    return nil, "No such handler"
end

-- Register a timer
Event.timer = function (timeout, callback, times)
    return Event.register {
        key = false,
        callback = callback,
        timeout = timeout,
        times = times or _infinity
    }
end

-- Blocking pull which only returns signals matching a filter
Event.pullFiltered = function (filter, timeout)
    checkArg(1, filter, "function")
    checkArg(2, timeout, "number", "nil")
    local deadline = _cUptime() + (timeout or _infinity)
    repeat
        local signal = table.pack(computer.pullSignal(deadline - _cUptime()))
        if filter(signal) then
            return table.unpack(signal, 1, signal.n)
        end
    until _cUptime() >= deadline
    return nil
end

-- Generates a filter that behaves like Event.pull
local createPlainFilter = function (...)
    local args = table.pack(...)
    return function (signal)
        for i = 1, #args do
            if args[i] ~= nil and args[i] ~= signal[i] then
                return false
            end
        end
        return true
    end
end

-- Blocking pull that matches a single event template
Event.pull = function (first, ...)
    local filter, timeout
    if type(first) == "number" then
        timeout = first
        filter = createPlainFilter(...)
    else
        timeout = _infinity
        filter = createPlainFilter(first, ...)
    end
    return Event.pullFiltered(filter, timeout)
end

-- Generates a filter that behaves like Event.pullMultiple
local createMultiFilter = function (...)
    local args = table.pack(...)
    return function (signal)
        for i = 1, #args do
            if args[i] == signal[1] then
                return true
            end
        end
        return false
    end
end

-- Blocking pull that matches one of a list of keys
Event.pullMultiple = function (...)
    local filter, timeout
    if type(first) == "number" then
        timeout = first
        filter = createMultiFilter(...)
    else
        timeout = _infinity
        filter = createMultiFilter(first, ...)
    end
    return Event.pullFiltered(filter, timeout)
end

-- Push a signal into the back of the signal buffer
Event.push = computer.pushSignal

-- Spin until the event buffer is completely empty, OR the timeout occurs
-- Returns -1 if timed out, otherwise number of loops needed to flush
Event.flush = function (timeout)
    checkArg(1, timeout, "number", "nil")
    local deadline = _cUptime() + (timeout or _infinity)
    local sequence = 0
    repeat
        Event.push("event_flush", sequence)
        -- If we immediately pull the same signal, the buffer is empty.
        local signal = table.pack(Event.pull(0))
        if signal[1] == "event_flush" and signal[2] == sequence then
            return sequence
        end
        -- Otherwise, wait until it's pulled, so the buffer cycles once
        Event.pull("event_flush", sequence)
        sequence = sequence + 1
    until _cUptime() >= deadline
    return false
end

computer.pullSignal = hookedPull
return Event
