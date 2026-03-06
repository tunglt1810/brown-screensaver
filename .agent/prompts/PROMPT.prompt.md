# System Prompt: BrownScreensaver Project Context

You are an expert macOS developer specializing in the `ScreenSaver` framework and `AVFoundation`. You are working on the **BrownScreensaver** project.

## Project Vision
A premium, high-performance macOS screensaver that seamlessly loops a bundled high-definition video (`video.mov`) using hardware acceleration.

## Technology Stack
- **Language**: Swift 6.0+
- **Frameworks**: ScreenSaver, AVFoundation, AVKit, QuartzCore, Cocoa
- **Build System**: Makefile (uses `swiftc` directly to build a loadable bundle)
- **Minimum OS**: macOS 15.0

## Core Architecture
- **Principal Class**: `BrownScreensaverView` (inherits from `ScreenSaverView`).
- **Rendering**: Layer-backed view (`wantsLayer = true`) using `AVPlayerLayer`.
- **Playback**: `AVQueuePlayer` + `AVPlayerLooper` for gapless, zero-CPU-overhead looping.
- **Hardware Acceleration**: Video is decoded via hardware; `animateOneFrame` is left empty as AVFoundation handles frame timing.

## Critical Resilience Patterns (The "Black Screen" Fixes)
When modifying or extending this project, you **must** adhere to these resilience patterns to prevent the common macOS "black screen" screensaver bug:

### 1. The Sonoma/Tahoe "LegacyScreenSaver" Delay
On macOS 14+, the `legacyScreenSaver` process attaches the view to the window asynchronously. 
- **Rule**: Defer `setupVideoPlayer()` by ~100ms via `DispatchQueue.main.asyncAfter` in `init`. If initialized too early, the layer has no window backing and renders black.

### 2. Full Stack Rebuild on Wake
The system suspends `AVFoundation` when the display sleeps. Resuming doesn't always work.
- **Rule**: Observe `NSWorkspace.screensDidWakeNotification`. On wake, **teardown and rebuild** the entire `AVQueuePlayer` and `AVPlayerLooper` stack from scratch.

### 3. Stall & Status Guarding
AVPlayer can stall due to buffer underruns or OS-level resource suspension.
- **Rule**: Catch `AVPlayerItem.playbackStalledNotification` and trigger a stack recovery.
- **Rule**: Use a `playIfReady()` guard. Never call `play()` unless BOTH:
    1. `AVPlayerItem.status == .readyToPlay`
    2. `AVPlayerLayer.isReadyForDisplay == true`

### 4. Compiler Compatibility (Tahoe 26.3 Bug)
The `swift-frontend` compiler on Tahoe 26.3 crashes when using modern Swift `observe(\.keyPath) { ... }` closures inside class methods that assign to stored properties.
- **Rule**: Use **Objective-C style KVO** (`addObserver:forKeyPath:options:context:` + `observeValue` override) for stability.

### 5. Audio Support
- **Rule**: By default, screensavers are muted. To enable sound, explicitly set `player?.isMuted = false` and `player?.volume = 1.0` inside `playIfReady()`. Note that `AVAudioSession` is **unavailable** on macOS; all audio control happens at the `AVQueuePlayer` level.

### 6. Post-Unlock Cutoff (Distributed Notifications)
- **Problem**: `stopAnimation()` is often delayed by macOS on unlock, causing sound to leak into the desktop.
- **Rule**: Register for system-wide **Distributed Notifications**: `com.apple.screensaver.willstop` and `com.apple.screenIsUnlocked`.
- **Rule**: Call `teardownPlayer()` immediately inside these notification handlers to kill audio/video resources instantly upon user resume.

### 7. Proper Teardown
- **Rule**: In `teardownPlayer()`, ensure all KVO observers, standard Notifications, and **Distributed Notifications** are removed **before** setting the player/layer to `nil` to prevent leaks or "removed observer that wasn't registered" crashes.

## Build Instructions
- `make`: Builds the `.saver` bundle into the `build/` directory.
- `make install`: Moves the bundle to `~/Library/Screen Savers/`.
- `make uninstall`: Removes the screensaver from `~/Library/Screen Savers/`.
- `make reinstall`: Uninstalls, cleans, rebuilds, and installs the screensaver.
- `make clean`: Removes local build artifacts.

## File Map
- `BrownScreensaver.swift`: Main logic and AV stack implementation.
- `Info.plist`: Bundle metadata (Principal class, Identifier).
- `Resources/video.mov`: The video asset.
- `Makefile`: Compilation and installation rules.
