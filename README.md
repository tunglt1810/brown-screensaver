# Brown Screensaver

A macOS screensaver that plays a video in a loop.

## Motivation

This project was created because the original Line screensaver app stopped working starting from macOS 15 (Sequoia) and has not been updated. This is a modern, Swift-based alternative that works seamlessly on the latest macOS versions.

## Features

- Plays `video.mov` from the Resources folder with hardware acceleration
- Loops seamlessly and gaplessly using `AVPlayerLooper`
- **Premium Resilience**: Guaranteed to never leak audio/video into the background after unlock (tested on macOS 14+ Sonoma/Tahoe)
- **Multi-Monitor Logic**: Automatically mutes secondary monitors to prevent audio echoing
- Native Apple Silicon (arm64) support
- Uses `thumbnail.png` as the preview image in System Settings
- Compatible with macOS 15+ (Sequoia)

## Building

To build the screensaver:

```bash
make
```

## Installation

To install the screensaver to your system:

```bash
make install
# If you get permission denied errors:
sudo make reinstall
```

This will copy the screensaver to `~/Library/Screen Savers/`.

After installation:
1. Open **System Settings**
2. Go to **Screen Saver**
3. Select **BrownScreensaver** from the list

## Testing

To test the screensaver without installing:

```bash
make test
```

This will open the screensaver bundle in Finder.

## Uninstallation

To remove the screensaver:

```bash
make uninstall
```

## Development

The screensaver is written in Swift and uses:
- `ScreenSaver.framework` - macOS screensaver API
- `AVFoundation` - Video playback
- `AVKit` - Video player layer

### File Structure

```
brown-screensaver/
├── BrownScreensaver.swift    # Main screensaver code
├── Info.plist                # Bundle configuration
├── Makefile                  # Build script
├── Resources/                # Assets
│   ├── video.mov            # Video to play
│   ├── thumbnail.png        # Preview thumbnail
│   └── ...                  # Localization files
└── README.md                # This file
```

## Vibe Coding

This project is a product of **Vibe Coding** — built entirely through a collaborative partnership with **Antigravity** and powered by **Gemini 2.0 Pro**. No manual code was written by the user; the entire implementation, debugging, and documentation were architected through AI-driven pair programming.

## Credits

- Developed for macOS 15+ (Sequoia / Tahoe)
- Powered by **Antigravity** & **Gemini 2.0 Pro**
- Built with **Cursor** & **Claude 3.7 Sonnet** (Model cascade)
- Replaces the legacy Line screensaver

## Disclaimer

This project is intended for **personal use only**. 

**Copyright Notice**: The character "Brown" is a trademark and copyright of **LINE Corporation**. This project is not affiliated with, endorsed by, or sponsored by LINE Corporation. The use of any character-related assets in this repository is strictly for personal, non-commercial purposes as a fan-made alternative to the original screensaver.

## License

This project is open-source and available under the [MIT License](LICENSE).
