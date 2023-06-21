local event = {
    handlers = {}
}

-- Local copies of required vars, as they will be intercepted or hidden
local computer_uptime = computer.uptime
local math_huge = math.huge

--------------------------------------------------------------------------------
-- Handler API

local function registerHandler(key, callback, interval, times, opt_handlers)
    local handler = {
        key = key,
        times = times or 1,
        callback = callback,
        interval = interval or math.huge
    }
    handler.timeout = computer_uptime() + handler.interval
    opt_handlers = opt_handlers or event.handlers

    -- Find a suitable slot
    local id = 0
    repeat
        id = id + 1
    until not opt_handlers[id]

    -- TODO: Should I save the ID in the handler?
    opt_handlers[id] = handler
    return id
end

local shouldHandlerTrigger = function (handler, signal)
    return (handler.key == nil)
        or (handler.key == signal)
        or (computer_uptime() >= handler.timeout)
end

local triggerHandler = function (id, handler, eventData)
    handler.times = handler.times - 1
    handler.timeout = handler.timeout + handler.interval
    -- We need to remove handlers before calling their callbacks, in case of
    -- timers that pull. And we need to make sure that the handler still exists
    -- because callbacks may have unregister things.
    if handler.times <= 0 and handlers[id] == handler then
        handlers[id] = nil
    end
    -- Call the handler
    local ok, result = pcall(handler.callback,
        table.unpack(eventData, 1, eventData.n))
    if not ok then
        -- TODO: Catch errors in event handlers
    -- Unregister handler if its own callback tells us to
    elseif result == false and handlers[id] == handler then
        handlers[id] = nil
    end
end

local dispatchHandlers = function (eventData)
    local signal = eventData[1]
    -- Make a copy of event.handlers because we'll be modifying it
    local copy = {}
    for k, v in pairs(event.handlers) do
        copy[k] = v
    end
    -- Trigger every handler that should be triggered
    for id, handler in pairs(copy) do
        if shouldHandlerTrigger(handler, signal) then
            triggerHandler(id, handler, eventData)
        end
    end
end

--------------------------------------------------------------------------------
-- Intercept computer.pullSignal to dispatch event handlers

local _pullSignal = computer.pullSignal
local pullSignal = function (seconds)
    checkArg(1, seconds, "number", "nil")
    seconds = seconds or math_huge
    local deadline = computer_uptime() + seconds
    repeat
        -- Find closest deadline
        local closest = deadline
        for _, handler in pairs(event.handlers) do
            closest = math.min(handler.timeout, closest)
        end

        local eventData = table.pack(_pullSignal(closest - computer_uptime()))
        dispatchHandlers(eventData)
        if eventData[1] then
            return table.unpack(eventData, 1, eventData.n)
        end
    until computer_uptime() >= deadline
end

computer.pullSignal = pullSignal

--------------------------------------------------------------------------------
-- Filter generators

local createPlainFilter = function (name, ...)
    local filter = table.pack(...)
    if name == nil and filter.n == 0 then
        return nil
    end

    return function(...)
        local signal = table.pack(...)
        if name and not (type(signal[1]) == "string" and signal[1]:match(name)) then
            return false
        end
        for i = 1, filter.n do
            if filter[i] ~= nil and filter[i] ~= signal[i + 1] then
                return false
            end
        end
        return true
    end
end

local createMultipleFilter = function (...)
    local filter = table.pack(...)
    if filter.n == 0 then
        return nil
    end

    return function(...)
        local signal = table.pack(...)
        if type(signal[1]) ~= "string" then
            return false
        end
        for i = 1, filter.n do
            if filter[i] ~= nil and signal[1]:match(filter[i]) then
                return true
            end
        end
        return false
    end
end

--------------------------------------------------------------------------------
-- Listeners

event.listen = function (name, callback)
    checkArg(1, name, "string")
    checkArg(2, callback, "function")
    
    -- Avoid registering the same listener twice
    for _, handler in pairs(event.handlers) do
        if handler.key == name and handler.callback == callback then
            return nil
        end
    end
    return registerHandler(name, callback, math_huge, math_huge)
end

event.ignore = function (name, callback)
    checkArg(1, name, "string")
    checkArg(2, callback, "function")
    for id, handler in pairs(event.handlers) do
        if handler.key == name and handler.callback == callback then
            event.handler[id] = nil
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Timers

event.interval = function (interval, callback, times)
    checkArg(1, interval, "number")
    checkArg(2, callback, "function")
    checkArg(3, times, "number", "nil")
    times = times or math_huge
    return registerHandler(false, callback, interval, times)
end

event.timeout = function (interval, callback)
    return event.interval(interval, callback, 1)
end

event.cancel = function (id)
    checkArg(1, id, "number")
    if event.handlers[id] then
        event.handlers[id] = nil
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Blocking pulls

local pullEvents = function (seconds, filter)
    seconds = seconds or math_huge
    repeat
        local signal = table.pack(pullSignal(seconds))
        if signal.n > 0 then
            if not (seconds or filter) or filter == nil or
                    filter(table.unpack(signal, 1, signal.n)) then
                return table.unpack(signal, 1, signal.n)
            end
        end
    until signal.n == 0
end

event.pull = function (...)
    local args = table.pack(...)
    if type(args[1]) == "string" then
        return pullEvents(nil, createPlainFilter(...))
    else
        checkArg(1, args[1], "number", "nil")
        checkArg(2, args[2], "string", "nil")
        return pullEvents(args[1], createPlainFilter(select(2, ...)))
    end
end

event.pullFiltered = function (...)
    local args = table.pack(...)
    if type(args[1]) == "function" then
        return pullEvents(nil, args[1])
    else
        checkArg(1, args[1], "number", "nil")
        checkArg(2, args[2], "function", "nil")
        return pullEvents(args[1], args[2])
    end
end

event.pullMultiple = function (...)
    local args = table.pack(...)
    if type(args[1]) == "string" then
        return pullEvents(nil, createMultipleFilter(...))
    else
        checkArg(1, args[1], "number", "nil")
        checkArg(2, args[2], "string", "nil")
        return pullEvents(args[1], createMultipleFilter(select(2, ...)))
    end
end

--------------------------------------------------------------------------------
-- Manually fire events

event.push = computer.pushSignal

return event
