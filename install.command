#!/bin/bash

# MuseCollab 1-Click Mac Installer
# Double-click this file in Mac Finder to install the plugin!

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "================================================================"
echo "          🎵  MuseCollab 1-Click Plugin Installer"
echo "================================================================"
echo ""

# If node is installed, use install.js
if command -v node &> /dev/null; then
    node "$DIR/install.js"
    echo ""
    read -p "Press [Enter] to close..."
    exit 0
fi

# Fallback: pure bash copy (No Node required!)
echo "Node.js not found, using macOS built-in installer..."
echo ""

TARGET_DIR="$HOME/Documents/MuseScore4/Plugins/MuseCollab"

if [ ! -d "$HOME/Documents/MuseScore4/Plugins" ]; then
    if [ -d "$HOME/Library/Audio/Plug-Ins/MuseScore4/Plugins" ]; then
        TARGET_DIR="$HOME/Library/Audio/Plug-Ins/MuseScore4/Plugins/MuseCollab"
    elif [ -d "$HOME/Documents/MuseScore3/Plugins" ]; then
        TARGET_DIR="$HOME/Documents/MuseScore3/Plugins/MuseCollab"
    fi
fi

mkdir -p "$TARGET_DIR"
cp -R "$DIR/plugin/." "$TARGET_DIR/"

echo "================================================================"
echo "       ✅  MuseCollab Plugin Installed Successfully!"
echo "================================================================"
echo ""
echo "Installed to: $TARGET_DIR"
echo "Server: https://musescore-collab.onrender.com (Pre-configured!)"
echo ""
echo "Next Steps:"
echo "  1. Open MuseScore"
echo "  2. Go to: Plugins → Manage Plugins (or Preferences → Plugins)"
echo "  3. Check [✓] MuseCollab"
echo "  4. Open from top menu: Plugins → MuseCollab"
echo ""
read -p "Press [Enter] to close..."
