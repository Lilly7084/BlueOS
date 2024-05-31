do
    -- Some limitations have been imposed on the project; enforce them here
    component.proxy = nil  -- We can't use that, remember?
    -- Bootstrap implementation of loadfile
    local invoke = component.invoke
    local eeprom = component.list("eeprom")() or error("Missing EEPROM")
    local hdd = invoke(eeprom, "getData") or error("Missing boot filesystem")
    local loadfile = function (path)
        local handle, reason = invoke(hdd, "open", path, "r")
        if not handle then
            return nil, reason
        end
        local buffer = ""
        repeat
            local chunk = invoke(hdd, "read", handle, 0x20000)
            buffer = buffer .. (chunk or "")
        until not chunk
        invoke(hdd, "close", handle)
        return load(buffer, "=" .. path, "t", _G)
    end
    -- Call /System/Startup.lua, which contains the actual startup process
    loadfile("/System/Startup.lua")(loadfile)
end

-- Hang indefinitely
while true do
    require("Computer").pullSignal()
end
