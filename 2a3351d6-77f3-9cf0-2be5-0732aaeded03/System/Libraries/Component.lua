local Component = _G.component
local proxies = {}
local primaries = {}

local Event = require("Event")

-- Resolve an abbreviated address to a full address
-- Optionally specify component type to filter results
Component.get = function (addr, ctype)
    checkArg(1, addr, "string")
    checkArg(2, ctype, "string", "nil")
    -- TODO: Use filter built into Component.list to make search faster?
    for thatAddr, thatCtype in Component.list() do
        if string.sub(thatAddr, 1, #addr) == addr and (ctype == nil or ctype == thatCtype) then
            return thatAddr
        end
    end
    return nil, "No such component"
end

-- Metatable for proxy methods: invocation and doc strings
local mtMethod = {
    -- i.e. gpu.setResolution(...)
    __call = function (self, ...)
        return Component.invoke(self.address, self.name, ...)
    end,
    -- i.e. gpu.setResolution in print(), shows documentation if available
    __tostring = function (self)
        return Component.doc(self.address, self.name) or "function"
    end
}

-- Metatable for proxy objects: makes fields appear as part of the proxy itself
local mtProxy = {
    __index = function(self, key)
        if self.fields[key] and self.fields[key].getter then
            return Component.invoke(self.address, key)
        else
            rawget(self, key)
        end
    end,
    __newindex = function(self, key, value)
        if self.fields[key] and self.fields[key].setter then
            return Component.invoke(self.address, key, value)
        elseif self.fields[key] and self.fields[key].getter then
            error("Field is read-only")
        else
            rawset(self, key, value)
        end
    end,
    __pairs = function(self)
        local keyProxy, keyField, value
        return function()
            if not keyField then
                repeat
                    keyProxy, value = next(self, keyProxy)
                until not keyProxy or keyProxy ~= "fields"
            end
            if not keyProxy then
                keyField, value = next(self.fields, keyField)
            end
            return keyProxy or keyField, value
        end
    end
}

-- Assemble a proxy object for a component, given a full address
Component.proxy = function (addr)
    checkArg(1, addr, "string")
    -- Use cache when possible
    if proxies[addr] then
        return proxies[addr]
    end
    -- Gather information needed to assemble the proxy
    local ctype, reason = bpcall(Component.type, addr)
    if not ctype then
        return nil, reason
    end
    local slot, reason = bpcall(Component.slot, addr)
    if not slot then
        return nil, reason
    end
    local methods, reason = bpcall(Component.methods, addr) -- [method] = 
    if not methods then
        return nil, reason
    end
    local fields, reason = bpcall(Component.fields, addr) -- [method] = {getter,setter}
    if not fields then
        return nil, reason
    end
    -- And now assemble the proxy
    local proxy = {
        address = addr,
        type = ctype,
        slot = slot
    }
    for method, direct in pairs(methods) do
        proxy[method] = setmetatable({
            address = addr,
            name = method
        }, mtMethod)
    end
    for field, info in pairs(fields) do
        proxy.fields[field] = info
    end
    -- Add it to the cache so this work doesn't need to be done again
    setmetatable(proxy, mtProxy)
    proxies[addr] = proxy
    return proxy
end

-- Check whether a primary component of a given type is available
Component.isAvailable = function (ctype)
    checkArg(1, ctype, "string")
    return primaries[ctype] ~= nil
end

-- Retrieve the primary component of a given type
Component.getPrimary = function (ctype)
    checkArg(1, ctype, "string")
    local proxy = primaries[ctype]
    if not proxy then
        return nil, "No such component"
    end
    return proxy
end

-- Set or remove the primary component of a given type
Component.setPrimary = function (ctype, addr)
    checkArg(1, ctype, "string")
    checkArg(2, addr, "string", "nil")
    if addr ~= nil then
        -- Bind
        if not Component.isAvailable(ctype) then
            primaries[ctype] = Component.proxy(addr)
            Event.push("component_available", ctype)
            return true
        end
        return nil, "Component already available"
    else
        -- Unbind
        if Component.isAvailable(ctype) then
            primaries[ctype] = nil
            Event.push("component_unavailable", ctype)
            return true
        end
        return nil, "No such component"
    end
end

-- Syntactic sugar for retrieving primaries, i.e. Component.gpu
setmetatable(Component, {
    __index = function (self, key)
        return Component.getPrimary(key)
    end
})

-- Support hot-plugging components
Event.listen("component_added", function (_, addr, ctype)
    Component.setPrimary(ctype, addr)
end)
Event.listen("component_removed", function (_, addr, ctype)
    Component.setPrimary(ctype, nil)
end)

-- Register all components which were present at boot time
for addr, ctype in Component.list() do
    Event.push("component_added", addr, ctype)
end

return Component
