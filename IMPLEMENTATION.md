# Brown Screensaver - Implementation Summary

## Overview

A macOS screensaver for macOS 15+ (Sequoia) that plays a video from `Resources/video.mov` in a seamless loop.

## Project Structure

```
brown-screensaver/
├── BrownScreensaver.swift          # Main screensaver implementation (Swift)
├── Info.plist                      # Bundle configuration
├── Makefile                        # Build system
├── install.sh                      # Quick installation script
├── README.md                       # Main documentation
├── .gitignore                      # Git ignore rules
├── Resources/                      # Static assets
│   ├── video.mov                  # Video file to play
│   ├── thumbnail.png              # Preview thumbnail
│   └── *.lproj/                   # Localization files
└── build/                         # Build artifacts (gitignored)
    └── BrownScreensaver.saver/    # Final screensaver bundle
```

## Implemented Features

### 1. Video Playback
- ✅ Plays video from `Resources/video.mov`.
- ✅ Seamless looping using `AVPlayerLooper`.
- ✅ Automatic scaling to fill the screen (`resizeAspectFill`).
- ✅ Muted by default for a non-intrusive experience.

### 2. ScreenSaver Integration
- ✅ Inherits from `ScreenSaverView` as a public class.
- ✅ Implements key lifecycle methods:
  - `init(frame:isPreview:)` - View initialization.
  - `startAnimation()` - Starts video playback.
  - `stopAnimation()` - Pauses playback when inactive.
  - `animateOneFrame()` - Standard update cycle (handled by AVPlayer).
- ✅ Explicitly defined `hasConfigureSheet = false`.

### 3. Layout & Resizing
- ✅ Dynamic resizing of the video layer on window size changes.
- ✅ Support for both preview mode (in System Settings) and full-screen activation.
- ✅ Robust cleanup in `deinit`.

### 4. Build System
- ✅ Makefile targets:
  - `make` - Builds the screensaver.
  - `make install` - Installs to `~/Library/Screen Savers/`.
  - `make uninstall` - Removes the screensaver.
  - `make clean` - Clears build directory.
  - `make test` - Opens the bundle for inspection.
- ✅ `install.sh` script for one-click installation.

## Technical Details

### Frameworks Used
- `ScreenSaver.framework` - macOS Screen Saver API.
- `AVFoundation` - Video playback and processing.
- `AVKit` - Media rendering UI.
- `QuartzCore` - Core Animation for layer management.

### Video Looping Implementation
```swift
let playerItem = AVPlayerItem(url: videoURL)
let queuePlayer = AVQueuePlayer(playerItem: playerItem)
self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
```
`AVPlayerLooper` ensures zero delay between the end and restart of the video.

### Compilation as a Bundle
The screensaver is compiled as a loadable bundle (`MH_BUNDLE`) using the `-Xlinker -bundle` flag, which is essential for the macOS screensaver system to load the binary dynamically.

## Usage

### Build and Install
```bash
# Using the script:
./install.sh

# Or using make:
make clean
make install
```

### Activate Screensaver
1. Open **System Settings**.
2. Go to **Screen Saver**.
3. Select **BrownScreensaver** from the list.
4. Click **Preview** to verify.

## Compatibility
- **macOS Version**: 15.0+ (Sequoia).
- **Architecture**: Apple Silicon (arm64).
- **Swift Version**: 5.x+.

## Logging
The screensaver logs activity to `Console.app` with the prefix `BrownScreensaverView:` for easy debugging of loading and playback states.

To view logs in real-time:
```bash
log stream --predicate 'processImagePath contains "BrownScreensaver"' --level debug
```

## Known Limitations
1. Video must be in `.mov` format (extension can be added).
2. No configuration UI (simplified design).
3. Always muted (consistent with modern defaults).

## Credits
- Developed specifically for macOS 15+.
- Modern Swift implementation replacing legacy Line screensaver.
