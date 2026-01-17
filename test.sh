#!/bin/bash
# Test screensaver directly without installing

set -e

echo "🔨 Building screensaver..."
make clean > /dev/null 2>&1
make > /dev/null 2>&1

echo "✅ Build complete!"
echo ""
echo "🎬 Opening screensaver for testing..."
echo ""
echo "Tip: Double-click the .saver file to preview it"
echo "     or right-click and choose 'Open' to install it"
echo ""

open build/BrownScreensaver.saver
