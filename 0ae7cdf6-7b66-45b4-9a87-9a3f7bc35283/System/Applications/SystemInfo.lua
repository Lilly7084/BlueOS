local computer = require("Computer")
local filesystem = require("Filesystem")

print(_OSVERSION .. ", " .. _VERSION)
print("Uptime: " .. computer.uptime() .. "s")

local batterySize = computer.maxEnergy()
local batteryLevel = computer.energy()
local percent = math.ceil(batteryLevel * 100 / batterySize)
if percent > 100 then percent = 100 end
print("Battery: " .. percent .. "%")

local totalMemory = computer.totalMemory()
local usedMemory = totalMemory - computer.freeMemory()
percent = math.ceil(usedMemory * 100 / totalMemory)
if percent > 100 then percent = 100 end
print("Memory usage: " .. tostring(usedMemory) .. "/" .. tostring(totalMemory) .. " bytes (" .. tostring(percent) .. "%)")

local function formatDriveInfo(name, proxy)
    local totalSpace = proxy.spaceTotal()
    local usedSpace = proxy.spaceUsed()
    local percent = math.ceil(usedSpace * 100 / totalSpace)
    return name .. " : " .. proxy.address .. ", " .. tostring(usedSpace) .. "/" 
        .. tostring(totalSpace) .. " bytes (" .. tostring(percent) .. "%) used"
end

print("")
print("Mounted file systems:")
for proxy, path in filesystem.mounts() do
    print("  - " .. formatDriveInfo(path, proxy))
end
