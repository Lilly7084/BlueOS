local Component = _G.component
local proxies = {}

-- REMEMBER: We don't have component.proxy from the machine,
-- so we'll need to implement that ourself (including docs in field __tostring)

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
    if not ctype then return nil, reason end
    local slot, reason = bpcall(Component.slot, addr)
    if not slot then return nil, reason end
    local methods, reason = bpcall(Component.methods, addr) -- [method] = 
    if not methods then return nil, reason end
    local fields, reason = bpcall(Component.fields, addr) -- [method] = {getter,setter}
    if not fields then return nil, reason end
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

-- TODO: Maintain a cache of proxies for 'primary' components
-- TODO: Support hot-plugging components

return Component
