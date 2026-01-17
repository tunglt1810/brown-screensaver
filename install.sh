#!/bin/bash
# Quick install script for Brown Screensaver

set -e

echo "🎬 Building Brown Screensaver..."
make clean
make

echo ""
echo "📦 Installing to ~/Library/Screen Savers..."
make install

echo ""
echo "✅ Installation complete!"
echo ""
echo "To activate the screensaver:"
echo "1. Open System Settings"
echo "2. Go to 'Screen Saver'"
echo "3. Select 'BrownScreensaver' from the list"
echo ""
echo "To test immediately, run:"
echo "  open ~/Library/Screen\\ Savers/BrownScreensaver.saver"
