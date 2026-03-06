# Architecture Overview

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    BrownScreensaver                         │
│                  (ScreenSaverView)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              AVPlayerLayer                           │  │
│  │  (Displays video content)                            │  │
│  │                                                       │  │
│  │  Properties:                                          │  │
│  │  - videoGravity: .resizeAspectFill                   │  │
│  │  - autoresizingMask: width/height sizable            │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ▲                                  │
│                          │                                  │
│                          │ player                           │
│                          │                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              AVQueuePlayer                           │  │
│  │  (Manages video playback)                            │  │
│  │                                                       │  │
│  │  Properties:                                          │  │
│  │  - isMuted: true                                      │  │
│  │  - rate: 1.0 (when playing)                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ▲                                  │
│                          │                                  │
│                          │ templateItem                     │
│                          │                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              AVPlayerLooper                          │  │
│  │  (Handles seamless looping)                          │  │
│  │                                                       │  │
│  │  Automatically replays video without gaps            │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ▲                                  │
│                          │                                  │
│                          │ url                              │
│                          │                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              AVPlayerItem                            │  │
│  │  (Represents video.mov)                              │  │
│  │                                                       │  │
│  │  Source: Bundle(for: type(of: self))/video.mov       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Lifecycle Flow

```
┌──────────────┐
│   macOS      │
│ ScreenSaver  │
│   System     │
└──────┬───────┘
       │
       │ 1. Load bundle
       ▼
┌──────────────────────────────────────┐
│ init(frame:isPreview:)               │
│ - Create view (isAnimating = false)  │
│ - Call configureView()               │
└──────┬───────────────────────────────┘
       │
       │ 2. Configure View
       ▼
┌──────────────────────────────────────┐
│ configureView()                      │
│ - Set wantsLayer = true              │
│ - Initialize background & layout     │
│ - (Video setup is DEFERRED)          │
└──────┬───────────────────────────────┘
       │
       │ 3. Start Animation
       ▼
┌──────────────────────────────────────┐
│ startAnimation()                     │
│ - isAnimating = true                 │
│ - isTornDown = false                 │
│ - isIntentionalPause = false         │
│ - Delayed setupVideoPlayer()         │
└──────┬───────────────────────────────┘
       │
       │ 4. Setup Video Stack
       ▼
┌──────────────────────────────────────┐
│ setupVideoPlayer()                   │
│ - Guard !isAnimating                 │
│ - Rebuild AV stack (Item/Looper)     │
│ - Register KVO & Notifications       │
└──────┬───────────────────────────────┘
       │
       │ 5. Running
       ▼
┌──────────────────────────────────────┐
│ playIfReady()                        │
│ - Guard isAnimating && !isTornDown   │
│ - Sync Multi-Monitor Audio Lock      │
│ - player.play()                      │
└──────┬───────────────────────────────┘
       │
       │ 6. Stop / Teardown
       ▼
┌──────────────────────────────────────┐
│ stopAnimation() / viewDidMoveToWindow│
│ - isIntentionalPause = true          │
│ - teardownPlayer()                   │
│ - isTornDown = true                  │
│ - Remove all observers               │
│ - Kill AV stack (disable looping)    │
└──────────────────────────────────────┘
```

## Resilience & Background Prevention

To prevent video/audio from leaking into the background (especially after Face ID unlock or screen sleep), the architecture employs a "Triple-Guard" strategy:

### 1. State Guarding Flags
- **`isAnimating`**: Native macOS flag. Prevents starting playback if the system hasn't officially started the screensaver.
- **`isIntentionalPause`**: Prevents KVO "stall" recovery from firing when the OS intentionally pauses the player for screen sleep.
- **`isTornDown`**: Blocks all delayed `DispatchQueue` tasks (async setup or recovery) from creating/playing a player after the user has already returned to the desktop.

### 2. Reliable Cleanup
- **Overriding `viewDidMoveToWindow`**: macOS often fails to call `stopAnimation()` reliably on unlock. Overriding this view lifecycle method ensures `teardownPlayer()` is called whenever the view is detached from the UI.
- **Distributed Notifications**: Listens for `com.apple.screenIsUnlocked` and `com.apple.screensaver.willstop` for immediate, system-wide teardown of AV resources.
- **Aggressive AV Termination**: `teardownPlayer()` explicitly calls `playerLooper?.disableLooping()` and `player?.removeAllItems()` to force the AVFoundation stack to stop completely before release.

### 3. Asymmetric Setup
- **Delay (macOS 14+)**: On Sonoma/Tahoe, `legacyScreenSaver` attaches views asynchronously. A 100ms delay in `startAnimation` ensures the `AVPlayerLayer` has a valid window backing before rendering, avoiding the "black screen" bug.
- **Deferred Initialization**: The `AVPlayer` stack is not created until `startAnimation` is called, preventing "zombie players" that might exist if the OS initializes the view but never displays it.

## Video Looping Mechanism

```
AVPlayerLooper automatically handles looping:

Time: 0s ──────────────────────────────────────────────────►
      │                                                      │
      ▼                                                      ▼
   ┌─────────────┐  End reached  ┌─────────────┐  End reached
   │ Play video  │──────────────►│ Play video  │──────────────►
   │ (Loop 1)    │  Auto restart │ (Loop 2)    │  Auto restart
   └─────────────┘               └─────────────┘

No gap between loops - seamless playback!
```

## Bundle Structure

```
BrownScreensaver.saver/
│
├── Contents/
│   │
│   ├── Info.plist ─────────────► Bundle metadata
│   │                              - CFBundleIdentifier
│   │                              - NSPrincipalClass
│   │                              - LSMinimumSystemVersion
│   │
│   ├── MacOS/
│   │   └── BrownScreensaver ───► Compiled loadable bundle
│   │                              (Mach-O arm64 bundle)
│   │
│   └── Resources/
│       ├── video.mov ──────────► Video file (1.6MB)
│       ├── thumbnail.png ──────► Preview image (30KB)
│       └── en.lproj/ ──────────► Localization files
```

## Build Process

```
┌──────────────────┐
│ Source Files     │
│ - .swift         │
│ - Info.plist     │
│ - Resources/     │
└────────┬─────────┘
         │
         │ make
         ▼
┌──────────────────┐
│ Swift Compiler   │
│ (swiftc)         │
└────────┬─────────┘
         │
         │ Compile with frameworks:
         │ - ScreenSaver
         │ - AVFoundation
         │ - AVKit
         │ - Cocoa
         ▼
┌──────────────────┐
│ Mach-O Bundle    │
└────────┬─────────┘
         │
         │ Package into bundle
         ▼
┌──────────────────┐
│ .saver Bundle    │
│ (Ready to use)   │
└────────┬─────────┘
         │
         │ make install
         ▼
┌──────────────────┐
│ ~/Library/       │
│ Screen Savers/   │
└──────────────────┘
```

## Key Design Decisions

### 1. Why AVPlayerLooper?
- **Seamless looping**: No gap between video end and restart.
- **Automatic**: No manual replay logic needed.
- **Efficient**: Optimized by Apple for this use case.

### 2. Why resizeAspectFill?
- **Full screen coverage**: No black bars.
- **Maintains aspect ratio**: No distortion.
- **Professional look**: Consistent with modern macOS aesthetics.

### 3. Why muted by default?
- **User expectation**: Screensavers are typically silent.
- **Non-intrusive**: Won't interrupt background audio or disturb others.

### 4. Why no configuration sheet?
- **Simplicity**: Focus on playing the high-quality video.
- **Quick implementation**: Minimal friction for the user.

## Performance Considerations

### Memory Usage
- AVPlayer uses hardware acceleration.
- Video is streamed efficiently.
- Minimal overall memory footprint (~50-100MB).

### CPU Usage
- Hardware-accelerated video decoding.
- Minimal CPU impact (~1-5%).
- Energy-efficient playback suitable for long durations.

### Startup Time
- Instant initialization (~100-200ms).
- Video begins playing as soon as the screensaver activates.
