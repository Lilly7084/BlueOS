local component = require("Component")

local framebuf = {}
local drivers = {}

--[[
    [*] General management
    framebuf.hasDriver(driver: string): boolean
        Checks whether a framebuffer driver with a specified name is available
    framebuf.getAvailableDrivers(): function () -> string
        Creates an iterator over all available framebuffer drivers
    framebuf.new(w: number, h: number, driver: string) -> table [1]
        Create a new framebuffer object
    framebuf.screen
        Framebuffer object which represents the currently bound display
    
    [*] Driver names
        "screen" = Data stored in video RAM, presented directly to screen
        "cpu" = Data stored in CPU, all operations done in software
        "vram" = Data stored in video RAM, all operations done on GPU. Will
            fall back on "cpu" driver if remaining video RAM is too little.

    [1] Frame buffer objects
    fb:destroy()
        Destroys the buffer and frees the memory that it occupies.
    fb:size()
        Returns width and height, in characters
    fb:resize(w: number, h: number, clearColor: number)
        Resizes the buffer to the requested dimension, filling in any newly
        created character spaces with the specified clear color.
    fb:clear(clearColor: number)
        Fills the entire frame buffer with solid color rectangles to clear it.
    fb:set(x: number, y: number, text: string, fg: number, bg: number)
        Copies text into the buffer at the specified location, with the
        specified foreground and background colors.
    fb:get(x: number, y: number)
        Returns the character, foreground color, and background color at the
        specified location.
    fb:fill(x: number, y: number, w: number, h: number, char: string, fg: number, bg: number)
        Fills the specified area with a single colored character.
    fb:clone(srcX: number, srcY: number, w: number, h: number, dstX: number, dstY: number)
        Copies the data at a specified location onto another location.
    fb:crop([[x: number, y: number,] w: number, h: number])
        Creates a cropped copy of the current buffer. X and Y default to top
        left corner. Width and height default to the full buffer size.
    fb:blit(other: table, srcX: number, srcY: number, w: number, h: number, dstX: number, dstY: number)
        Like clone(), but reads the data from a different frame buffer.
    
    [1] Hidden member objects in framebuffers
    fb.width
        Width of buffer, in characters
    fb.height
        Height of buffer, in characters
    fb.buffer
        Raw buffer (CPU)
        Handle to the appropriate video RAM allocation (VRAM)
    fb.proxy
        Proxy to the graphics card the buffer resides on (screen or VRAM)
]]

--------------------------------------------------------------------------------
-- Common code

framebuf.hasDriver = function (name)
    checkArg(1, name, "string")
    for driverName, _ in pairs(drivers) do
        if driverName:lower() == name:lower() then
            return true
        end
    end
    return false
end

framebuf.getAvailableDrivers = function ()
    local name
    return function ()
        name, _ = next(drivers, name)
        return name
    end
end

framebuf.new = function (width, height, driverName)
    checkArg(1, width, "number")
    checkArg(2, height, "number")
    checkArg(3, driverName, "string")
    if not framebuf.hasDriver(driverName) then
        return nil, 'No such framebuffer driver'
    end
    -- Make a copy of the driver methods
    local fbuf = {}
    for key, value in pairs(drivers[driverName]) do
        fbuf[key] = value
    end
    -- Call constructor
    fbuf:init(width, height)
    return fbuf
end

local fbufSize = function (self)
    return self.width, self.height
end

--------------------------------------------------------------------------------
-- Screen buffer

local proxy = component.getPrimary("gpu")
local width, height = proxy.maxResolution()
framebuf.screen = {
    name = "screen",
    width = width,
    height = height,
    buffer = nil,
    proxy = proxy
}

framebuf.screen.destroy = function (self)
    error("Screen buffer cannot be destroyed!")
end

framebuf.screen.size = fbufSize

framebuf.screen.resize = function (self, width, height, clearColor)
    local oldWidth, oldHeight = self.proxy.getResolution()
    local maxWidth, maxHeight = self.proxy.maxResolution()
    self.width = math.min(width, maxWidth)
    self.height = math.min(height, maxHeight)
    self.proxy.setResolution(width, height)
    self.proxy.setBackground(clearColor)
    self.proxy.fill(oldWidth + 1, 1, self.width - oldWidth, self.height, " ")
    self.proxy.fill(1, oldHeight + 1, self.width, self.height - oldHeight, " ")
    return oldWidth, oldHeight
end

framebuf.screen.set = function (self, x, y, text, fgColor, bgColor)
    self.proxy.setForeground(fgColor)
    self.proxy.setBackground(bgColor)
    -- TODO: Word wrap in screen driver set()?
    self.proxy.set(x, y, text)
end

framebuf.screen.get = function (self, x, y)
    return self.proxy.get(x, y) -- char, fg, bg
end

framebuf.screen.clear = function (self, clearColor)
    self.proxy.setBackground(clearColor)
    self.proxy.fill(1, 1, self.width, self.height, " ")
end

framebuf.screen.fill = function (self, x, y, width, height, char, fgColor, bgColor)
    self.proxy.setForeground(fgColor)
    self.proxy.setBackground(bgColor)
    -- self.proxy.fill(x, y, width, height, char:sub(1, 1))
    self.proxy.fill(x, y, width, height, char)
end

framebuf.screen.clone = function (self, srcX, srcY, width, height, dstX, dstY)
    self.proxy.copy(srcX, srcY, width, height, dstX - srcX, dstY - srcY)
end

framebuf.screen.crop = function (...)
    error("Crop functionality is not ready yet!")
end

-- Unoptimized blit routine, not using special GPU methods
local screen_blit_basic = function (fbuf, srcX, srcY, width, height, dstX, dstY)
    for y = 0, height-1 do
        for x = 0, width-1 do
            local chr, fg, bg = fbuf:get(x + srcX, y + srcY)
            component.gpu.setForeground(fg)
            component.gpu.setBackground(bg)
            component.gpu.set(x + dstX, y + dstY, chr)
        end
    end
end

framebuf.screen.blit = function (self, other, ...)
    if other == self then
        return self:clone(...)
    end
    if other.name == "cpu" then
        return screen_blit_basic(other, ...)
    end
    error("Required blit functionality is not ready yet!")
end

framebuf.screen:clear(0x000000)

--------------------------------------------------------------------------------
-- CPU framebuffer driver

drivers.cpu = { name = "cpu" }

drivers.cpu.init = function (self, width, height)
    checkArg(1, width, "number")
    checkArg(2, height, "number")
    local DEFAULT_FG = 0xFFFFFF
    local DEFAULT_BG = 0x000000
    self.width = width
    self.height = height
    self.proxy = nil
    self.buffer = { chr = {}, fg = {}, bg = {} }
    for y = 1, height do
        local chr, fg, bg = {}, {}, {}
        for x = 1, width do
            table.insert(chr, " ")
            table.insert(fg, DEFAULT_FG)
            table.insert(bg, DEFAULT_BG)
        end
        table.insert(self.buffer.chr, chr)
        table.insert(self.buffer.fg, fg)
        table.insert(self.buffer.bg, bg)
    end
end

drivers.cpu.destroy = function (self)
    -- There's no hardware that needs to be freed here
end

drivers.cpu.size = fbufSize

drivers.cpu.resize = function (self)
    error("Resizing CPU buffers hasn't been implemented yet!")
end

local cpu_put = function (self, x, y, ch, fg, bg)
    if x > 0 and x <= self.width and y > 0 and y <= self.height then
        self.buffer.chr[y][x] = ch
        self.buffer.fg[y][x] = fg
        self.buffer.bg[y][x] = bg
    end
end

drivers.cpu.set = function (self, x, y, text, fg, bg)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, text, "string")
    checkArg(4, fg, "number")
    checkArg(5, bg, "number")
    for i = 1, #text do
        cpu_put(self, x+i-1, y, string.sub(text, i, i), fg, bg)
    end
end

drivers.cpu.get = function (self, x, y)
    if x <= 0 or x > self.width or y <= 0 or y > self.height then
        return nil, "Coordinates out of range"
    end
    return self.buffer.chr[y][x], self.buffer.fg[y][x], self.buffer.bg[y][x]
end

drivers.cpu.clear = function (self, clearColor)
    self:fill(1, 1, self.width, self.height, " ", clearColor, clearColor)
end

drivers.cpu.fill = function (self, x, y, w, h, char, fg, bg)
    char = string.sub(char, 1, 1)
    for py = y, y+h-1 do
        for px = x, x+w-1 do
            self.buffer.chr[py][px] = char
            self.buffer.fg[py][px] = fg
            self.buffer.bg[py][px] = bg
        end
    end
end

drivers.cpu.clone = function (self, ...)
    self:blit(self, ...)
end

drivers.cpu.crop = function (...)
    error("Crop functionality is not ready yet!")
end

drivers.cpu.blit = function (self, other, srcX, srcY, width, height, dstX, dstY)
    -- Choose scan direction so this can work like a memmove()
    local xStart, xEnd, xStep, yStart, yEnd, yStep
    if srcX > dstX then
        xStart = width - 1
        xEnd = 0
        xStep = -1
    else
        xStart = 0
        xEnd = width - 1
        xStep = 1
    end
    if srcY > dstY then
        yStart = height - 1
        yEnd = 0
        yStep = -1
    else
        yStart = 0
        yEnd = height - 1
        yStep = 1
    end
    -- Copy (can't optimize with gpu.blit(), etc)
    for y = yStart, yEnd, yStep do
        for x = xStart, xEnd, xStep do
            local chr, fg, bg = other:get(srcX + x, srcY + y)
            self.buffer.chr[dstY + y][dstX + x] = chr
            self.buffer.fg[dstY + y][dstX + x] = fg
            self.buffer.bg[dstY + y][dstX + x] = bg
        end
    end
end

--------------------------------------------------------------------------------

return framebuf
