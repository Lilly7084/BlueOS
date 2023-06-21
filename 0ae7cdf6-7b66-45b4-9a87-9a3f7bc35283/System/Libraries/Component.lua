local event = require("Event")

local component = _G.component

local installed = {}
local installing = {}

-- Expand a shortened address to a full address,
-- and return the proxy if it could be found
component.get = function (address, componentType)
    checkArg(1, address, "string")
    checkArg(2, componentType, "string", "nil")
    for c in component.list(componentType, true) do
        -- TODO: This is case-sensitive and sensitive to dashes
        if c:sub(1, address:len()) == address then
            return c, installed[c]
        end
    end
    return nil, "No such component"
end

-- Check whether a primary component of the specified type exists
component.isAvailable = function (componentType)
    checkArg(1, componentType, "string")
    return installed[componentType] ~= nil
end

-- Check whether a component is the primary of its type
component.isPrimary = function (address)
    local componentType = component.type(address)
    if componentType then
        if component.isAvailable(componentType) then
            return installed[componentType].address == address
        end
    end
    return false
end

-- Get the primary component of a given type
component.getPrimary = function (componentType)
    checkArg(1, componentType, "string")
    assert(component.isAvailable(componentType),
        "No primary component of type \"" .. componentType .. "\" exists")
    return installed[componentType]
end

-- Install a component as primary
component.setPrimary = function (componentType, address)
    checkArg(1, componentType, "string")
    checkArg(2, address, "string", "nil")

    -- If we're given a component, make sure it exists
    if address ~= nil then
        address = component.get(address, componentType)
        assert(address, "No such component")
    end

    -- Quit if component is already installed or BEING installed
    local isInstalled = installed[componentType]
    if isInstalled and address == isInstalled.address then
        return
    end
    local isInstalling = installing[componentType]
    if isInstalling and address == isInstalling.address then
        return
    end

    -- If another primary was set to install, cancel it
    if isInstalling then
        event.cancel(isInstalling.timer)
    end
    -- Mark this component type as completely unused
    installed[componentType] = nil
    installing[componentType] = nil

    -- Notify the rest of the system if we uninstalled a component
    if isInstalled then
        event.push("component_unavailable", componentType)
    end

    if address then
        local proxy = component.proxy(address)
        -- If a component previously existed, stall the installation a bit
        if isInstalled or isInstalling then
            installing[componentType] = {
                address = address,
                proxy = proxy,
                timer = event.timer(0.1, function()
                    installing[componentType] = nil
                    installed[componentType] = proxy
                    event.push("component_available", componentType)
                end)
            }
        else
            installed[componentType] = proxy
            event.push("component_available", componentType)
        end
    end
end

--------------------------------------------------------------------------------
-- Automatically install and uninstall components (hotplug)

local function onComponentAdded(_, address, componentType)
    if not component.isAvailable(componentType) then
        component.setPrimary(componentType, address)
    end
end

local function onComponentRemoved(_, address, componentType)
    if component.isAvailable(componentType) then
        component.setPrimary(componentType, nil)
    end
end

event.listen("component_added", onComponentAdded)
event.listen("component_removed", onComponentRemoved)

--------------------------------------------------------------------------------
-- Automatically install every component on boot

-- Prioritize boot filesystem as primary filesystem
local bootFS = component.get(computer.getBootAddress(), "filesystem")
if bootFS then
    event.push("component_added", bootFS, "filesystem")
end

for address, componentType in component.list() do
    event.push("component_added", address, componentType)
end

--------------------------------------------------------------------------------
-- Syntactic sugar: use component.gpu instead of component.getPrimary("gpu")

setmetatable(component, {
    __index = function(_, key)
        return component.getPrimary(key)
    end
})

--------------------------------------------------------------------------------

return component
