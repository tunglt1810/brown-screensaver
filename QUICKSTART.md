# QuickStart Guide - Brown Screensaver

## Quick Installation

```bash
./install.sh
```

Or:

```bash
make install
```

## Activation

1. Open **System Settings**
2. Select **Screen Saver**
3. Select **BrownScreensaver** from the list
4. Set the wait time (e.g., 5 minutes)

## Test Immediately

```bash
open ~/Library/Screen\ Savers/BrownScreensaver.saver
```

## Uninstallation

```bash
make uninstall
```

## Changing the Video

1. Replace the file `Resources/video.mov` with your new video
2. Rebuild and install: `make clean && make install`

## View Logs

```bash
log stream --predicate 'processImagePath contains "BrownScreensaver"' --level debug
```

## Notes

- The video will loop automatically
- Sound is muted by default
- Supports macOS 15+ (Sequoia)
