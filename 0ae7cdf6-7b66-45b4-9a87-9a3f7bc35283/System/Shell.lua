local event = require("Event")
local filesystem = require("Filesystem")
local framebuf = require("Framebuf")
local keyboard = require("Keyboard")

framebuf.screen:clear(0x000000)
local width, height = framebuf.screen:size()
local OUTPUT_BOX_HEIGHT = height - 3
local INPUT_BOX_X = 1
local INPUT_BOX_Y = height - 2
local INPUT_BOX_HEIGHT = 3

-- Make the input box
framebuf.screen:set(1, INPUT_BOX_Y, "┌", 0xFFFFFF, 0x000000)
framebuf.screen:set(width, INPUT_BOX_Y, "┐", 0xFFFFFF, 0x000000)
framebuf.screen:set(1, INPUT_BOX_Y + 2, "└", 0xFFFFFF, 0x000000)
framebuf.screen:set(width, INPUT_BOX_Y + 2, "┘", 0xFFFFFF, 0x000000)
framebuf.screen:fill(2, INPUT_BOX_Y, width - 2, INPUT_BOX_HEIGHT, "─", 0xFFFFFF, 0x000000)
framebuf.screen:fill(1, INPUT_BOX_Y + 1, width, 1, "│", 0xFFFFFF, 0x000000)
framebuf.screen:fill(2, INPUT_BOX_Y + 1, width - 2, 1, " ", 0xFFFFFF, 0x000000)

print = function (str)
    str = tostring(str)
    framebuf.screen:clone(1, 2, width, OUTPUT_BOX_HEIGHT - 1, 1, 1)
    framebuf.screen:fill(1, OUTPUT_BOX_HEIGHT, width, 1, " ", 0xFFFFFF, 0x000000)
    framebuf.screen:set(1, OUTPUT_BOX_HEIGHT, str, 0xFFFFFF, 0x000000)
end

local runInput = function (command)
    if command:len() == 0 then return end
    print("")
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

    framebuf.screen:fill(INPUT_BOX_X + 2, INPUT_BOX_Y + 1, width - 4, 1, " ", 0xFFFFFF, 0x000000)
    framebuf.screen:set(INPUT_BOX_X + 2, INPUT_BOX_Y + 1, inputBuffer .. "█", 0xFFFFFF, 0x000000)
end

updateInput(nil, nil, 0, 0, nil)
event.listen("key_down", updateInput)

while true do
    event.pull()
end
