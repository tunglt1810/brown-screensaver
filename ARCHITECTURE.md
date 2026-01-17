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
│ - Create view                        │
│ - Call configureView()               │
└──────┬───────────────────────────────┘
       │
       │ 2. Setup
       ▼
┌──────────────────────────────────────┐
│ configureView() & setupVideoPlayer() │
│ - Load video.mov from bundle         │
│ - Create AVPlayerItem                │
│ - Create AVQueuePlayer               │
│ - Setup AVPlayerLooper               │
│ - Create AVPlayerLayer               │
│ - Add layer to view                  │
│ - Mute audio                         │
└──────┬───────────────────────────────┘
       │
       │ 3. Start
       ▼
┌──────────────────────────────────────┐
│ startAnimation()                     │
│ - player.play()                      │
│ - Video starts playing               │
└──────┬───────────────────────────────┘
       │
       │ 4. Running
       ▼
┌──────────────────────────────────────┐
│ animateOneFrame()                    │
│ - Called periodically                │
│ - No action needed (AVPlayer auto)   │
└──────┬───────────────────────────────┘
       │
       │ 5. Stop
       ▼
┌──────────────────────────────────────┐
│ stopAnimation()                      │
│ - player.pause()                     │
│ - Video pauses                       │
└──────┬───────────────────────────────┘
       │
       │ 6. Cleanup
       ▼
┌──────────────────────────────────────┐
│ deinit                               │
│ - Remove observers                   │
│ - Release player                     │
│ - Release looper                     │
└──────────────────────────────────────┘
```

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
