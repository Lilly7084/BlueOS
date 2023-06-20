#!/bin/sh
project_dir=$(pwd)
cd ~/Downloads/OCEmu/src
# '> /dev/null' - Shut up.
lua boot.lua --basedir=${project_dir} > /dev/null
