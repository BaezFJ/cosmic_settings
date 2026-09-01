#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Updating system"
sudo apt update && sudo apt upgrade -y

"$SCRIPT_DIR/install-uv.sh"
"$SCRIPT_DIR/install-node-latest.sh" --lts
"$SCRIPT_DIR/install-github-cli.sh"
"$SCRIPT_DIR/install-chrome-stylus-catppuccin.sh"
"$SCRIPT_DIR/install-jetbrains-toolbox.sh"
"$SCRIPT_DIR/sync-catppuccin-walls.sh"
