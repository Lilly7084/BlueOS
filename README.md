# bOS

This is a custom operating system I've been working on for the Minecraft mod
OpenComputers. It works with the stock Lua BIOS, so it does not need to be
reflashed to work. Third-party upgrades, such as the EFI from
[MineOS](https://github.com/IgorTimofeev/MineOS/), work too, as long as they
support booting from `/init.lua`.

It's being developed for [OCEmu](https://github.com/zenith391/OCEmu), since it's
the first OpenComputers emulator I found with support for **off-screen frame
buffers**. This is a fairly new feature in OpenComputers, which allows you to
have images or pre-rendered content loaded in video RAM, which can be bitblit-ed
into the visible portion of memory with a single command. This is **huge**,
since it means tasks like showing the desktop background can be made so much
faster.

You _do_ need to have OCEmu installed, and need to direct it to the folder that
this project resides in. I will not be providing instructions for the former,
since OCEmu's repo explains how to do that. For the latter, these instructions
may be outdated by the time you read this, but as of __19th June 2023__, you
need to launch OCEmu as `lua boot.lua --basedir={path to project}`. I included
an executable shell script (`run.sh`) that does this for me, but do not expect
it to work the same for you.

Top-level contents:
  - `.vscode/` : Settings for my preferred code editor (Visual Studio Code)
  - `0ae7cdf6-7b66-45b4-9a87-9a3f7bc35283/` : Emulator's main drive
  - `3b13eaf5-3632-468b-a5cd-1fa2bd267ced/` : Emulator's EEPROM (stock)
  - `tmpfs/` : Emulator's temporary filesystem (ignore)
  - `ocemu.cfg` : Emulator settings
  - `README.md` : This
  - `run.sh` : Shell script I use to run the OS

## To-do list

Current features:
  - Event polling framework
  - Component hotplugging support
  - Filesystem driver
  - Temporary shell with cat test

Things I want to add soon:
  - Loading and executing command scripts
  - IO stream library
  - Loading spinner in boot menu

Things I want to add eventually:
  - Graphical user interface
  - Multi-tasking capability
  - Partial data card emulation, with:
    - Full hashing (CRC32, SHA256, and MD5)
    - Base64 encoding and decoding
    - _(Maybe)_ Deflate compression
    - _(Maybe)_AES encryption
  - Theming / palettes loaded from a file
  - Pathing information loaded from a file

Things I **never** want to add:
  - Complete data card emulation; `generateKeyPair()`, `ecdh()`, and `ecdsa()`
    are too advanced for me, and true random numbers can not be emulated at all

Bugs, that I know of:
  - _None so far, please report them if you find any!_

## Code credit:

[OpenOS](https://github.com/MightyPirates/OpenComputers): Event driver and parts of filesystem driver
[MineOS](https://github.com/IgorTimofeev/MineOS): Most of the filesystem driver
