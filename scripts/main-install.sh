#!/usr/bin/env bash

echo "Updating system"
sudo apt update && sudo apt upgrade -y

. ./install-uv.sh
. ./install-node-latest.sh --lts
. ./install-chrome-stylus-catppuccin.sh
. ./install-jetbrains-toolbox.sh
. ./sync-catppuccin-walls.sh
