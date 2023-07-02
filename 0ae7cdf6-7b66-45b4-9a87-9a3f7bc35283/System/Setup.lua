local invoke = ...

-- Version information
_G._OSVERSION = "BlueOS 0.1.0"

-- Get the GPU started
local screen = component.list("screen")()
local gpu = screen and component.list("gpu")()
local width, height
if gpu then
    invoke(gpu, "bind", screen)
    width, height = invoke(gpu, "maxResolution")
    invoke(gpu, "setResolution", width, height)
    invoke(gpu, "setForeground", 0x2D2D2D)
    invoke(gpu, "setBackground", 0xC0C0C0)
    invoke(gpu, "fill", 1, 1, width, height, " ")
end

local cursor = 1
local putline = function (line)
    -- Scroll the screen if necessary
    if cursor > height then
        cursor = cursor - 1
        invoke(gpu, "copy", 1, 2, width, height - 1, 0, -1)
        invoke(gpu, "fill", 1, cursor, width, 1, " ")
    end
    invoke(gpu, "set", 1, cursor, tostring(line))
    cursor = cursor + 1
end

-- Print a message to the screen, if it's possible to do so
local println = function (msg)
    if gpu then
        for text in string.gmatch(tostring(msg), "[^\r\n]+") do
            while #text > 0 do
                putline(string.sub(text, 1, width))
                text = string.sub(text, width + 1)
            end
        end
    end
end

-- Intercept panic() so failures can be seen on the screen
local _panic = panic
panic = function (...)
    local args = table.pack(...)
    local message = "*** panic():"
    for _, v in ipairs(args) do
        message = message .. " " .. tostring(v)
    end
    invoke(gpu, "setForeground", 0xFF0000)
    invoke(gpu, "setBackground", 0x000000)
    println(message)
    println(debug.traceback())
    _panic()
end

local package = dofile("/System/Package.lua")
package.loaded.package = package

-- Libraries included from boot
package.loaded.computer = computer
package.loaded.os = os

local preloadLibraries = {
    "Event",
    "Component",
    "Filesystem",
    "Keyboard",
    "Framebuf"
}

-- Prepare screen for UI require

-- Main box
local boxWidth, boxHeight = 40, 8
local boxX = math.floor(width / 2 - boxWidth / 2)
local boxY = math.floor(height / 2 - boxHeight / 2)
invoke(gpu, "setBackground", 0xE1E1E1)
invoke(gpu, "fill", boxX, boxY, boxWidth, boxHeight, " ")

local centrize = function (x)
    return math.floor(width / 2 - x / 2)
end

-- Title
local boxTitle = _OSVERSION
invoke(gpu, "setForeground", 0x2D2D2D)
invoke(gpu, "set", centrize(#boxTitle), boxY + 1, boxTitle)

local titleCase = function (str)
    return str:sub(1, 1):upper() .. str:sub(2)
end

local preloadCount = 1
local uiRequire = function (name)

    -- Library name
    local text = "Loading library: " .. titleCase(name)
    local x = centrize(#text)
    invoke(gpu, "setForeground", 0x2D2D2D)
    invoke(gpu, "fill", boxX, boxY + boxHeight - 3, boxWidth, 1, " ")
    invoke(gpu, "set", x, boxY + boxHeight - 3, text)

    -- Progress bar (empty)
    local barWidth = 32
    local x = centrize(barWidth)
    invoke(gpu, "setForeground", 0xC3C3C3)
    invoke(gpu, "set", x, boxY + boxHeight - 2, string.rep("─", barWidth))

    -- Progress bar (filled)
    local part = math.ceil(barWidth * preloadCount / #preloadLibraries)
    invoke(gpu, "setForeground", 0x00C0FF)
    invoke(gpu, "set", x, boxY + boxHeight - 2, string.rep("─", part))

    preloadCount = preloadCount + 1
    return require(name)
end

local lib = {}

for _, name in ipairs(preloadLibraries) do
    lib[name] = uiRequire(name)
    if lib.Event then
        lib.Event.push("init")
        lib.Event.pull("init")
    end
end

-- Clean up _G
_G.component = nil
_G.computer = nil
_G.os = nil

-- Wrap up
package.exists = lib.Filesystem.exists

-- Shell file path
return "/System/Shell_framebufTest.lua"
