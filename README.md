# BlueOS version 0.0.3

The eventual goal of this project is to make a multi-user, multitasking, graphical operating system for the Minecraft mod [OpenComputers](https://github.com/MightyPirates/OpenComputers). That's really a lot to do, though, so the minimum viable product (0.1.0) will be a single-user terminal-only OS.

## Features

Current features:
  - Dynamically-linked library cache and loader (better known as the `package` library)
  - Event routing framework, since this will be an event-driven OS
  - Component abstraction and hot-plugging support (WIP)
  - This does **not** use the `component.proxy` provided by the machine, since that can be implemented on the OS side with no performance detriment.

Desired features (0.1.0):
  - Filesystem wrapper with support for multiple volumes and removable media
  - Handle-based file I/O, including Unix-like `stdin`/`stdout`/`stderr` pseudo-files
  - Extra stdlib functions for protected calls and manipulating numbers and tables
  - Basic collection of command-line utilities + text editor to make new programs

Desired features (Stretch):
  - Graphical user interface with draggable windows
  - Convenient framebuffer and GUI widget libraries to simply app development
  - Integrated Development Environment with Lua syntax highlighting
  - Symbolic link support in filesystem driver
  - Merge volumes (file-level software RAID0) to support very large scale storage
  - Multi-terminal support, including thin-client terminals (over network connection)
  - Data card abstraction with software emulation for tier 1/2 calls
  - [Minitel](https://github.com/ShadowKatStudios/OC-Minitel) compatible network stack
  - Minitel RPC support, allowing components to be used over a network connection (if requested)

_Note that the lists of desired features may grow, since I almost certainly forgot some pieces._

## Where is everything?

Repository files:
```
[repo root]
|- 2a3351d6-77f3-9cf0-2be5-0732aaeded03/    Root of main hard drive
|- .gitignore
|- client.cfg                               Client config file for OCVM
'- README.md
```

The included `client.cfg` is used for my testing copy of [ocvm](https://github.com/payonel/ocvm). _The root of the repository_ should be used as the virtual machine path when running ocvm (as the argument after the executable name).

Main hard drive (`bootfs`) files:
```
[HDD root]
|- System
|  |- Libraries                             Core libraries
|  |  |- Component.lua                      Component abstraction and hot-plugging (WIP)
|  |  |- Event.lua                          Event routing (Untested)
|  |  '- Package.lua                        Dynamically-linked library cache and loader
|  '- Startup.lua                           Startup script called by /init.lua
'- init.lua                                 Entry point executed by BIOS
```

## Bugs

_None so far..._

## License
**MIT License**

Copyright 2024 Lilly7084

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
