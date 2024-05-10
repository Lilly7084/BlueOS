-- Run /System/Startup.lua in its own scope to delete unneeded vars afterwards
do
    local invoke = component.invoke
    local eeprom = component.list("eeprom")() or error("Missing EEPROM")
    local bootfs = invoke(eeprom, "getData") or error("Missing boot filesystem")
    local loadfile = function (path)
        local handle, reason = invoke(bootfs, "open", path, "r")
        if not handle then
            return nil, reason
        end
        local buffer = ""
        repeat
            local chunk = invoke(bootfs, "read", handle, math.maxinteger or math.huge)
            buffer = buffer .. (chunk or "")
        until not chunk
        invoke(bootfs, "close", handle)
        return load(buffer, "=" .. path, "t", _G)
    end
    loadfile("/System/Startup.lua")(loadfile)
end

-- Hang indefinitely
while true do
    require("Computer").pullSignal()
end
