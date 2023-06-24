local framebuf = require("Framebuf")

local fbuf = framebuf.new(80, 1, "cpu")
fbuf:clear(0xFFFFFF)
fbuf:set(1, 1, "The framebuffer driver is now working perfectly!", 0x404040, 0xFFFFFF)
for i = 1, 50 do
    framebuf.screen:blit(fbuf, 1, 1, 80, 1, 81, i)
end
