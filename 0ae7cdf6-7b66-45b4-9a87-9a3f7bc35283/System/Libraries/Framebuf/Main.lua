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

local fbufSize = function (self)
    return self.width, self.height
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
    fbuf.size = fbufSize
    -- Call constructor
    fbuf:init(width, height)
    return fbuf
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
-- Register drivers

local function addDriver(path)
    local driver = require(path)
    if not driver.valid then
        return
    end
    drivers[driver.name] = driver
end

addDriver("Framebuf/CPU")
-- OOPS: Forgot to remove this attempt to register a non-existent driver
-- addDriver("Framebuf/VRAM")

--------------------------------------------------------------------------------

return framebuf
