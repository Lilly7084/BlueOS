local Shell = {}

local Component = require("Component")
local Event = require("Event")

local gpu = Component.gpu
local width, height = gpu.getResolution()
gpu.fill(1, 1, width, height, " ") -- Clear the screen

-- Draw the frame around the input box
gpu.fill(2, height - 2, width - 2, 1, "─") -- Top
gpu.fill(2, height, width - 2, 1, "─") -- Bottom
gpu.set(1, height - 1, "│") -- Left
gpu.set(width, height - 1, "│") -- Right
gpu.set(1, height - 2, "┌") -- Top left
gpu.set(width, height - 2, "┐") -- Top right
gpu.set(1, height, "└") -- Bottom left
gpu.set(width, height, "┘") -- Bottom right

--------------------------------------------------------------------------------
-- Compensating for libraries which aren't implemented yet

-- IO:
local cursor = 1
local putLine = function (line)
    checkArg(1, line, "string")
    -- Scroll the screen up if needed
    if cursor > height - 3 then
        gpu.copy(1, 2, width, height - 4, 0, -1)
        gpu.fill(1, height - 3, width, 1, " ")
        cursor = height - 3
    end
    gpu.set(1, cursor, line)
    cursor = cursor + 1
end

print = function (fmt, ...)
    local text
    if type(fmt) == "string" then
        text = string.format(fmt, ...)
    else
        text = tostring(fmt)
    end
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        putLine(line)
    end
end

-- Keyboard:
local isPrintable = function (char)
    return char ~= nil and char >= 0x20 and char < 0x7F
end

--------------------------------------------------------------------------------

local optRequire = function (name)
    local success, mod = pcall(require, name)
    if success then
        return mod
    end
end

local env = setmetatable({}, {
    __index = function (self, key)
        _ENV[key] = _ENV[key] or optRequire(key)
        return _ENV[key]
    end
})

env.print = function (...)
    local args = table.pack(...)
    local text = {}
    for i, x in ipairs(args) do
        text[i] = tostring(x)
    end
    print(table.concat(text, " "))
end

env.printTab = function (name, tbl, fmt)
    checkArg(1, name, "string")
    checkArg(2, tbl, "table")
    checkArg(3, fmt, "function", "nil")
    if fmt == nil then
        fmt = function (x) return tostring(x) end
    end
    print("%s:", name)
    for k, v in pairs(tbl) do
        print("  - %s = %s", k, fmt(v))
    end
end

local runIDLE = function (line)
    print(">>> %s", line)
    local code, reason
    if string.sub(line, 1, 1) == "=" then
        code, reason = load("return " .. string.sub(line, 2), "=stdin", "t", env)
    else
        code, reason = load("return " .. line, "=stdin", "t", env)
        if not code then
            code, reason = load(line, "=stdin", "t", env)
        end
    end
    if not code then
        print("Load error: %s", reason or "unknown error")
        return
    end
    local response, reason = bpcall(code)
    if not response and reason then
        print("Exec error: %s", reason)
        return
    end
    if response ~= nil then
        print(tostring(response))
    end
end

local drawInputBox = function (text)
    -- TODO: if text is too long to fit in the box, this will overrun
    gpu.fill(3, height - 1, width - 4, 1, " ")
    gpu.set(3, height - 1, text .. "▂")
end
drawInputBox("")

local commandLine = ""
local onKeyPress = function (_, addr, char, code, player)
    if code == 14 then -- Backspace
        commandLine = string.sub(commandLine, 1, #commandLine - 1)
    elseif code == 28 then -- Enter
        runIDLE(commandLine) -- TODO actually run command
        commandLine = ""
    elseif isPrintable(char) then
        commandLine = commandLine .. (string.char(char) or "")
    end
    drawInputBox(commandLine)
end

Shell.start = function ()
    Event.listen("key_down", onKeyPress)
end

--------------------------------------------------------------------------------
return Shell
