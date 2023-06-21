local event = require("Event")

local keyboard = {
    pressedChars = {},
    pressedCodes = {}
}

--------------------------------------------------------------------------------

keyboard.isControl = function (char)
    return type(char) == "number" and (char < 0x20 or (char >= 0x7F and char <= 0x9F))
end

keyboard.isShiftDown = function ()
    return keyboard.pressedCodes[keyboard.keys.lshift] or keyboard.pressedCodes[keyboard.keys.rshift]
end

keyboard.isAltDown = function ()
    return keyboard.pressedCodes[keyboard.keys.lmenu] or keyboard.pressedCodes[keyboard.keys.rmenu]
end

keyboard.isControlDown = function ()
    return keyboard.pressedCodes[keyboard.keys.lcontrol] or keyboard.pressedCodes[keyboard.keys.rcontrol]
end

keyboard.isKeyDown = function (charOrCode)
    checkArg(1, charOrCode, "string", "number")
    if type(charOrCode) == "string" then
        return keyboard.pressedChars[charOrCode:byte()]
    elseif type(charOrCode) == "number" then
        return keyboard.pressedCodes[charOrCode]
    end
end

--------------------------------------------------------------------------------
-- Automatically detect key presses and releases

local onKeyUpdate = function (signal, _, char, code)
    keyboard.pressedChars[char] = signal == "key_down" or nil
    keyboard.pressedCodes[code] = signal == "key_down" or nil
end

event.listen("key_down", onKeyUpdate)
event.listen("key_up", onKeyUpdate)

--------------------------------------------------------------------------------
-- Scan code table

keyboard.keys = {
    -- Main block numbers
    ["1"] = 0x02,
    ["2"] = 0x03,
    ["3"] = 0x04,
    ["4"] = 0x05,
    ["5"] = 0x06,
    ["6"] = 0x07,
    ["7"] = 0x08,
    ["8"] = 0x09,
    ["9"] = 0x0A,
    ["0"] = 0x0B,
    -- Main block letters
    a = 0x1E,
    b = 0x30,
    c = 0x2E,
    d = 0x20,
    e = 0x12,
    f = 0x21,
    g = 0x22,
    h = 0x23,
    i = 0x17,
    j = 0x24,
    k = 0x25,
    l = 0x26,
    m = 0x32,
    n = 0x31,
    o = 0x18,
    p = 0x19,
    q = 0x10,
    r = 0x13,
    s = 0x1F,
    t = 0x14,
    u = 0x16,
    v = 0x2F,
    w = 0x11,
    x = 0x2D,
    y = 0x15,
    z = 0x2C,
    -- Main block symbols
    apostrophe = 0x28,
    at = 0x91,
    backspace = 0x0E,
    backslash = 0x2B,
    colon = 0x92,
    comma = 0x33,
    enter = 0x1C,
    equals = 0x0D,
    grave = 0x29,
    lbracket = 0x1A,
    lcontrol = 0x1D,
    lmenu = 0x38,
    lshift = 0x2A,
    minus = 0x0C,
    period = 0x34,
    rbracket = 0x1B,
    rcontrol = 0x9D,
    rmenu = 0xB8,
    rshift = 0x36,
    semicolon = 0x27,
    slash = 0x35,
    space = 0x39,
    tab = 0x0F,
    underline = 0x93,
    -- Keypad (numpad with numlock off)
    up = 0xC8,
    down = 0xD0,
    left = 0xCB,
    right = 0xCD,
    home = 0xC7,
    ["end"] = 0xCF,
    pageUp = 0xC9,
    pageDown = 0xD1,
    insert = 0xD2,
    delete = 0xD3,
    -- Control
    capsLock = 0x3A,
    numLock = 0x45,
    scrollLock = 0x46,
    pause = 0xC5,
    stop = 0x95,
    -- Function keys
    f1 = 0x3B,
    f2 = 0x3C,
    f3 = 0x3D,
    f4 = 0x3E,
    f5 = 0x3F,
    f6 = 0x40,
    f7 = 0x41,
    f8 = 0x42,
    f9 = 0x43,
    f10 = 0x44,
    f11 = 0x57,
    f12 = 0x58,
    f13 = 0x64,
    f14 = 0x65,
    f15 = 0x66,
    f16 = 0x67,
    f17 = 0x68,
    f18 = 0x69,
    f19 = 0x71,
    -- Numpad
    numpad0 = 0x52,
    numpad1 = 0x4F,
    numpad2 = 0x50,
    numpad3 = 0x51,
    numpad4 = 0x4B,
    numpad5 = 0x4C,
    numpad6 = 0x4D,
    numpad7 = 0x47,
    numpad8 = 0x48,
    numpad9 = 0x49,
    numpadPlus = 0x4E,
    numpadMinus = 0x4A,
    numpadMultiply = 0x37,
    numpadDivide = 0xB5,
    numpadPeriod = 0x53,
    numpadComma = 0xB3,
    numpadEnter = 0x9C,
    numpadEquals = 0x8D
}

--------------------------------------------------------------------------------
-- Create inverse mapping to look up names of scancodes

setmetatable(keyboard.keys, {
    __index = function(tbl, k)
        if type(k) ~= "number" then return end
        for name, value in pairs(tbl) do
            if value == k then
                return name
            end
        end
    end
})

--------------------------------------------------------------------------------

return keyboard
