-- Framebuf driver: CPU-bound framebuffers
local driver = {
    valid = true,
    name = "cpu"
}

driver.init = function (self, width, height)
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

driver.destroy = function (self)
    -- There's no hardware that needs to be freed here
end

driver.resize = function (self)
    error("Resizing CPU buffers hasn't been implemented yet!")
end

local cpu_put = function (self, x, y, ch, fg, bg)
    if x > 0 and x <= self.width and y > 0 and y <= self.height then
        self.buffer.chr[y][x] = ch
        self.buffer.fg[y][x] = fg
        self.buffer.bg[y][x] = bg
    end
end

driver.set = function (self, x, y, text, fg, bg)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, text, "string")
    checkArg(4, fg, "number")
    checkArg(5, bg, "number")
    for i = 1, #text do
        cpu_put(self, x+i-1, y, string.sub(text, i, i), fg, bg)
    end
end

driver.get = function (self, x, y)
    if x <= 0 or x > self.width or y <= 0 or y > self.height then
        return nil, "Coordinates out of range"
    end
    return self.buffer.chr[y][x], self.buffer.fg[y][x], self.buffer.bg[y][x]
end

driver.clear = function (self, clearColor)
    self:fill(1, 1, self.width, self.height, " ", clearColor, clearColor)
end

driver.fill = function (self, x, y, w, h, char, fg, bg)
    char = string.sub(char, 1, 1)
    for py = y, y+h-1 do
        for px = x, x+w-1 do
            self.buffer.chr[py][px] = char
            self.buffer.fg[py][px] = fg
            self.buffer.bg[py][px] = bg
        end
    end
end

driver.clone = function (self, ...)
    self:blit(self, ...)
end

driver.crop = function (...)
    error("Crop functionality is not ready yet!")
end

local forRange = function (src, dst, size)
    if src > dst then
        return size - 1, 0, -1
    else
        return 0, size - 1, 1
    end
end

driver.blit = function (self, other, srcX, srcY, width, height, dstX, dstY)
    -- Choose scan direction so this can work like a memmove()
    local xStart, xEnd, xStep = forRange(srcX, dstX, width)
    local yStart, yEnd, yStep = forRange(srcY, dstY, height)
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

return driver
