import ScreenSaver
import AVKit
import AVFoundation
import QuartzCore

// KVO context pointers — each var has a unique stable address used to identify observations
private var kvoItemStatus:      UInt8 = 0
private var kvoReadyForDisplay: UInt8 = 0
private var kvoTimeControl:     UInt8 = 0

@objc(BrownScreensaverView)
public class BrownScreensaverView: ScreenSaverView {

    // MARK: - Global State (Multi-Monitor Sync)
    // Ensures only one instance plays audio when multiple screensavers are active
    private static var activeAudioInstance: ObjectIdentifier?

    // MARK: - Private State

    private var playerLayer:  AVPlayerLayer?
    private var player:       AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    // Keep references to KVO-observed objects so we can safely remove observers on teardown
    private weak var observedItem:        AVPlayerItem?
    private weak var observedPlayerLayer: AVPlayerLayer?
    private weak var observedPlayer:      AVQueuePlayer?

    // Guard against concurrent recovery trips
    private var isRecovering = false
    private var isIntentionalPause = false
    private var isTornDown = false

    /// Returns true if the window is occluded (covered by another window like the Lock Screen).
    private var isWindowOccluded: Bool {
        guard let w = self.window else { return true }
        return !w.occlusionState.contains(.visible)
    }

    // MARK: - Initialization

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        NSLog("BrownScreensaver: init(frame:isPreview:) isPreview=\(isPreview)")
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        NSLog("BrownScreensaver: init(coder:)")
        configureView()
    }

    // MARK: - Setup

    private func configureView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor

        // Video setup is deferred to startAnimation() to avoid bugs where legacyScreenSaver 
        // initializes the view but never starts it, leaving zombie players.
    }

    private func setupVideoPlayer() {
        guard self.isAnimating else {
            NSLog("BrownScreensaver: setupVideoPlayer aborted, isAnimating == false")
            return
        }
        guard let videoURL = Bundle(for: type(of: self))
                .url(forResource: "video", withExtension: "mov") else {
            NSLog("BrownScreensaver: ERROR - video.mov not found in bundle")
            return
        }

        NSLog("BrownScreensaver: setupVideoPlayer()")
        teardownPlayer()
        isTornDown = false

        // Build the AV stack
        let item = AVPlayerItem(url: videoURL)
        item.preferredForwardBufferDuration = 5.0

        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = false
        queuePlayer.volume = 1.0
        queuePlayer.actionAtItemEnd = .none
        self.player = queuePlayer

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.playerLooper = looper

        let pLayer = AVPlayerLayer(player: queuePlayer)
        pLayer.frame = bounds
        pLayer.videoGravity = .resizeAspectFill
        pLayer.backgroundColor = NSColor.black.cgColor
        self.playerLayer = pLayer

        self.layer?.addSublayer(pLayer)

        // ── ObjC-style KVO (avoids Swift type-checker crash on Tahoe 26.3) ──

        if let firstItem = looper.loopingPlayerItems.first {
            observedItem = firstItem
            firstItem.addObserver(self, forKeyPath: "status",
                                  options: [.new], context: &kvoItemStatus)
            NotificationCenter.default.addObserver(
                self, selector: #selector(handlePlaybackStalled),
                name: AVPlayerItem.playbackStalledNotification, object: firstItem)
        }

        observedPlayerLayer = pLayer
        pLayer.addObserver(self, forKeyPath: "readyForDisplay",
                           options: [.new], context: &kvoReadyForDisplay)

        observedPlayer = queuePlayer
        queuePlayer.addObserver(self, forKeyPath: "timeControlStatus",
                                options: [.new], context: &kvoTimeControl)

        registerSleepWakeObservers()
    }

    // MARK: - KVO Handler

    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        switch context {
        case &kvoItemStatus:
            guard let item = object as? AVPlayerItem else { break }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    NSLog("BrownScreensaver: item readyToPlay")
                    self.playIfReady()
                } else if item.status == .failed {
                    NSLog("BrownScreensaver: item failed - \(String(describing: item.error))")
                    self.scheduleRecovery()
                }
            }

        case &kvoReadyForDisplay:
            guard let layer = object as? AVPlayerLayer else { break }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if layer.isReadyForDisplay {
                    NSLog("BrownScreensaver: playerLayer isReadyForDisplay=true")
                    self.playIfReady()
                }
            }

        case &kvoTimeControl:
            guard let p = object as? AVQueuePlayer else { break }
            DispatchQueue.main.async { [weak self] in
                // Only recover if the screensaver considers itself running
                guard let self = self, self.isAnimating else { return }
                if p.timeControlStatus == .paused && !self.isIntentionalPause {
                    NSLog("BrownScreensaver: timeControlStatus=paused unexpectedly - recovering")
                    self.scheduleRecovery()
                }
            }

        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Play Logic

    /// Calls play() only once both the item is ready AND the layer has a texture to display.
    /// Prevents the black-frame race where play() fires before the layer renders.
    private func playIfReady() {
        guard
            let p = player,
            let pLayer = playerLayer,
            pLayer.isReadyForDisplay,
            p.currentItem?.status == .readyToPlay
        else { return }

        guard self.isAnimating, !self.isTornDown else {
            NSLog("BrownScreensaver: playIfReady aborted, isAnimating=\(self.isAnimating), isTornDown=\(self.isTornDown)")
            return
        }

        NSLog("BrownScreensaver: isReadyForDisplay + readyToPlay (isPreview=\(isPreview)) - starting playback")

        // Multi-Monitor Audio Sync:
        // Only one instance should play audio. The first one to reach here claims the lock.
        if BrownScreensaverView.activeAudioInstance == nil {
            BrownScreensaverView.activeAudioInstance = ObjectIdentifier(self)
            NSLog("BrownScreensaver: Instance claimed audio lock")
        }

        let hasAudioLock = (BrownScreensaverView.activeAudioInstance == ObjectIdentifier(self))
        p.isMuted = !hasAudioLock
        p.volume = hasAudioLock ? 1.0 : 0.0

        p.play()

        NSLog("BrownScreensaver: Playing - volume=\(p.volume) muted=\(p.isMuted)")
    }

    // MARK: - Sleep / Wake / System Events

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleScreensSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreensWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Window occlusion: detect when the Lock Screen covers the screensaver window.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOcclusionChange),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        // Distributed Notifications: handle stop signals from the system.
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(handleForcedStop),
                       name: NSNotification.Name("com.apple.screensaver.willstop"), object: nil)
        dc.addObserver(self, selector: #selector(handleForcedStop),
                       name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func handleForcedStop() {
        NSLog("BrownScreensaver: handleForcedStop (DistributedNotification) — tearing down player")
        teardownPlayer()
    }

    /// Called when ANY window's occlusion state changes.
    /// When our window is covered (e.g. by the Lock Screen), mute + pause.
    /// When our window becomes visible again, unmute + resume.
    @objc private func handleOcclusionChange(_ notification: Notification) {
        guard let notifWindow = notification.object as? NSWindow,
              notifWindow === self.window else { return }

        if isWindowOccluded {
            NSLog("BrownScreensaver: window occluded (Lock Screen?) — muting and pausing")
            isIntentionalPause = true
            player?.isMuted = true
            player?.volume = 0.0
            player?.pause()
        } else {
            NSLog("BrownScreensaver: window visible again — resuming")
            isIntentionalPause = false
            // Re-apply audio based on the audio lock
            if let p = player {
                let hasAudioLock = (BrownScreensaverView.activeAudioInstance == ObjectIdentifier(self))
                p.isMuted = !hasAudioLock
                p.volume = hasAudioLock ? 1.0 : 0.0
                p.play()
                NSLog("BrownScreensaver: Resumed - volume=\(p.volume) muted=\(p.isMuted)")
            }
        }
    }

    @objc private func handleScreensSleep() {
        NSLog("BrownScreensaver: screens sleep - muting and pausing")
        isIntentionalPause = true
        player?.isMuted = true
        player?.volume = 0.0
        player?.pause()
    }

    @objc private func handleScreensWake() {
        NSLog("BrownScreensaver: screens wake - attempting muted resume")
        isIntentionalPause = false
        // On wake, attempt a simple muted resume. Do NOT rebuild the AV stack.
        // If the lock screen is active, occlusion handler will keep us muted.
        // If the player is truly broken, the KVO stall handler will trigger recovery.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.isAnimating, !self.isTornDown else { return }
            guard let p = self.player else { return }
            if self.isWindowOccluded {
                NSLog("BrownScreensaver: wake resume aborted — window is occluded")
                return
            }
            // Resume with correct audio state
            let hasAudioLock = (BrownScreensaverView.activeAudioInstance == ObjectIdentifier(self))
            p.isMuted = !hasAudioLock
            p.volume = hasAudioLock ? 1.0 : 0.0
            p.play()
            NSLog("BrownScreensaver: wake resumed - volume=\(p.volume) muted=\(p.isMuted)")
        }
    }

    // MARK: - Stall Handling

    @objc private func handlePlaybackStalled() {
        NSLog("BrownScreensaver: playback stalled - scheduling recovery")
        scheduleRecovery()
    }

    // MARK: - Recovery

    private func scheduleRecovery() {
        guard !isRecovering else { return }
        isRecovering = true
        NSLog("BrownScreensaver: scheduling full recovery in 1 s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if !self.isAnimating || self.isTornDown || self.isWindowOccluded {
                NSLog("BrownScreensaver: recovery cancelled (isAnimating=\(self.isAnimating), isTornDown=\(self.isTornDown), occluded=\(self.isWindowOccluded))")
                self.isRecovering = false
                return
            }
            self.recoverPlayback()
        }
    }

    /// Tears down and fully rebuilds the AV stack.
    private func recoverPlayback() {
        NSLog("BrownScreensaver: recoverPlayback - rebuilding AV stack")
        isRecovering = false
        guard self.isAnimating, !self.isTornDown, !self.isWindowOccluded else {
            NSLog("BrownScreensaver: recoverPlayback aborted (isAnimating=\(self.isAnimating), isTornDown=\(self.isTornDown), occluded=\(self.isWindowOccluded))")
            return
        }
        setupVideoPlayer()
        // Playback resumes automatically via observeValue once item + layer are ready.
    }

    // MARK: - Teardown

    private func teardownPlayer() {
        isTornDown = true
        isIntentionalPause = true
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(
            self, name: AVPlayerItem.playbackStalledNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        DistributedNotificationCenter.default().removeObserver(self)

        if let item = observedItem {
            item.removeObserver(self, forKeyPath: "status", context: &kvoItemStatus)
            observedItem = nil
        }
        if let layer = observedPlayerLayer {
            layer.removeObserver(self, forKeyPath: "readyForDisplay", context: &kvoReadyForDisplay)
            observedPlayerLayer = nil
        }
        if let p = observedPlayer {
            p.removeObserver(self, forKeyPath: "timeControlStatus", context: &kvoTimeControl)
            observedPlayer = nil
        }

        playerLooper?.disableLooping()
        player?.pause()
        player?.removeAllItems()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerLooper = nil

        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        // Release the audio lock if this instance owned it
        if BrownScreensaverView.activeAudioInstance == ObjectIdentifier(self) {
            NSLog("BrownScreensaver: Instance releasing audio lock")
            BrownScreensaverView.activeAudioInstance = nil
        }
    }

    deinit {
        teardownPlayer()
        NSLog("BrownScreensaver: deinit")
    }

    // MARK: - ScreenSaverView Lifecycle

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window == nil {
            NSLog("BrownScreensaver: viewDidMoveToWindow (window=nil) - tearing down player")
            teardownPlayer()
        }
    }

    public override func startAnimation() {
        super.startAnimation()
        NSLog("BrownScreensaver: startAnimation isPreview=\(isPreview)")
        isIntentionalPause = false
        isTornDown = false
        
        // If we tore down the player in stopAnimation, rebuild it now
        if player == nil {
            NSLog("BrownScreensaver: Player is nil, rebuilding for startAnimation")
            // Aerial pattern: on macOS 14+ (Sonoma / Tahoe) legacyScreenSaver attaches
            // the view to its window asynchronously. Starting AVFoundation too early
            // causes the player layer to render pure black. A short async delay fixes this.
            if #available(macOS 14.0, *) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self, self.isAnimating, !self.isTornDown else { return }
                    if self.player == nil {
                        self.setupVideoPlayer()
                    }
                }
            } else {
                setupVideoPlayer()
            }
        } else {
            playIfReady()
        }
    }

    public override func stopAnimation() {
        super.stopAnimation()
        NSLog("BrownScreensaver: stopAnimation (isPreview=\(isPreview))")
        isIntentionalPause = true
        
        // Aggressive teardown: release all AV resources immediately to prevent
        // audio leaking into the background when the Preview window is closed.
        teardownPlayer()
    }

    public override func draw(_ rect: NSRect) {
        // Layer-backed view — AVPlayerLayer handles all rendering
    }

    public override func animateOneFrame() {
        // AVFoundation drives frames — nothing to do here
    }

    public override var hasConfigureSheet: Bool { return false }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        playerLayer?.frame = bounds
    }
}
