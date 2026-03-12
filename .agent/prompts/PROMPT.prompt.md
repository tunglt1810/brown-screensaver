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

## Critical Resilience Patterns
When modifying this project, you **must** follow all rules below to prevent audio/video leaking into the background.

### 1. Deferred Initialization (No Zombie Players)
- **Rule**: NEVER call `setupVideoPlayer()` in `init` or `configureView`.
- **Rule**: ONLY initialize the AV stack inside `startAnimation()`.
- **Rule**: On macOS 14+ (Sonoma/Tahoe), add a **100ms `asyncAfter` delay** inside `startAnimation()` before calling `setupVideoPlayer()`. The `legacyScreenSaver` process attaches the view asynchronously — calling too early causes a black screen.
- **Rule**: Every async `DispatchQueue` block must guard with `self.isAnimating && !self.isTornDown` before proceeding.

### 2. Triple-State Guarding
Three boolean flags must be maintained at all times to control the player lifecycle:
- **`isAnimating`** (native): True only when macOS has officially started the screensaver.
- **`isIntentionalPause`**: Set `true` in `handleScreensSleep`, `stopAnimation`, and `teardownPlayer`. Prevents KVO `timeControlStatus` from triggering spurious "stall recovery" while the OS intentionally has the player paused.
- **`isTornDown`**: Set `true` in `teardownPlayer()`, cleared in `setupVideoPlayer()` and `startAnimation()`. Blocks all pending async blocks from creating a new player after the user has already returned to the desktop.

### 3. Window Occlusion Guard (The Lock Screen Fix)
`stopAnimation()` is NOT reliably called by macOS when waking to the Lock Screen. Use `NSWindow.occlusionState` to detect when the screensaver window is covered:

```swift
private var isWindowOccluded: Bool {
    guard let w = self.window else { return true }
    return !w.occlusionState.contains(.visible)
}
```

- **Rule**: Observe `NSWindow.didChangeOcclusionStateNotification`. On occlusion → mute + pause + `isIntentionalPause = true`. On becoming visible → unmute + resume.
- **Rule**: In `handleScreensWake`, attempt a **simple muted resume** (do NOT rebuild the AV stack). Check `isWindowOccluded` before unmuting.
- **Rule**: In `scheduleRecovery` and `recoverPlayback`, bail out if `isWindowOccluded` is true.
- **Rule**: Do NOT check `isWindowOccluded` in `playIfReady()` — the window occlusion state is not reliable at startup time.

### 4. Aggressive Teardown
- **Rule**: Override `viewDidMoveToWindow()` and call `teardownPlayer()` if `self.window == nil`.
- **Rule**: Register Distributed Notifications: `com.apple.screensaver.willstop` and `com.apple.screenIsUnlocked` → call `teardownPlayer()` immediately.
- **Rule**: In `teardownPlayer()`, call in order: `playerLooper?.disableLooping()`, `player?.pause()`, `player?.removeAllItems()`, then nil all references.
- **Rule**: In `teardownPlayer()`, remove ALL observers: `NSWorkspace.shared.notificationCenter`, `NotificationCenter.default` (for stall + occlusion), and `DistributedNotificationCenter.default()`.

### 5. Multi-Monitor Audio Sync
- **Rule**: Use a `static var activeAudioInstance: ObjectIdentifier?` to ensure only **one** instance plays audio. The first instance to reach `playIfReady()` claims the lock. All others must be muted (`volume = 0.0`, `isMuted = true`).
- **Rule**: Release the lock in `teardownPlayer()`.

### 6. Compiler Compatibility (Tahoe 26.3 Bug)
- **Rule**: NEVER use modern Swift `observe(\.keyPath)` closures. Use **Objective-C-style KVO** (`addObserver:forKeyPath:options:context:` + `observeValue` override) to avoid `swift-frontend` compiler crashes.

## Build Instructions
- `make`: Builds the `.saver` bundle into `build/`.
- `make install`: Installs to `~/Library/Screen Savers/`. Use `sudo` if you get permission denied.
- `make reinstall`: Full clean rebuild and install (recommended for testing).

## File Map
- `BrownScreensaver.swift`: All logic and AV stack.
- `Info.plist`: Bundle metadata (Principal class, Identifier).
- `Resources/video.mov`: The video asset.
- `Makefile`: Build and install rules.
