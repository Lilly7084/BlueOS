local component = require("Component")
local event = require("Event")
local filesystem = require("Filesystem")
local keyboard = require("Keyboard")

-- Get the GPU started
local width, height = component.gpu.maxResolution()
-- width = math.min(width, 80)
-- height = math.min(height, 25)
component.gpu.setResolution(width, height)
component.gpu.setForeground(0xFFFFFF)
component.gpu.setBackground(0x000000)
component.gpu.fill(1, 1, width, height, " ")

print = function (str)
    str = tostring(str)
    component.gpu.copy(1, 2, width, height - 4, 0, -1)
    component.gpu.fill(1, height - 3, width, 1, " ")
    component.gpu.set(1, height - 3, str)
end

-- Draw input text box
local inputX = 3
local inputY = height - 1
local inputWidth = width - 4
component.gpu.set(1, inputY - 1, "┌")
component.gpu.fill(2, inputY - 1, width - 2, 1, "─")
component.gpu.set(width, inputY - 1, "┐")
component.gpu.set(1, inputY, "│")
component.gpu.set(width, inputY, "│")
component.gpu.set(1, inputY + 1, "└")
component.gpu.fill(2, inputY + 1, width - 2, 1, "─")
component.gpu.set(width, inputY + 1, "┘")

local runInput = function (command)
    if command:len() == 0 then return end
    print("> " .. command)
    local i = string.find(command, " ")
    if i then
        command = command:sub(1, i - 1)
    end
    local path = filesystem.concat("/System/Applications/", command .. ".lua")
    if not filesystem.exists(path) then
        print("*** Program \"" .. command .. "\" not found!")
        return
    end
    xpcall(loadfile(path), print)
end

local inputBuffer = ""
local updateInput = function (_, _, char, code, playerName)
    if code == keyboard.keys.enter then
        runInput(inputBuffer)
        inputBuffer = ""
    elseif code == keyboard.keys.backspace then
        inputBuffer = inputBuffer:sub(0, -2)
    elseif not keyboard.isControl(char) then
        -- TODO: Make sure input is printable char
        inputBuffer = inputBuffer .. string.char(char)
    end

    component.gpu.fill(inputX, inputY, inputWidth, 1, " ")
    component.gpu.set(inputX, inputY, inputBuffer .. "█")
end

updateInput(nil, nil, 0, 0, nil)
event.listen("key_down", updateInput)

while true do
    event.pull()
end
