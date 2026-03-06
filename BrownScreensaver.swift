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

        // Aerial pattern: on macOS 14+ (Sonoma / Tahoe) legacyScreenSaver attaches
        // the view to its window asynchronously. Starting AVFoundation too early
        // causes the player layer to render pure black. A short async delay fixes this.
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupVideoPlayer()
            }
        } else {
            setupVideoPlayer()
        }
    }

    private func setupVideoPlayer() {
        guard let videoURL = Bundle(for: type(of: self))
                .url(forResource: "video", withExtension: "mov") else {
            NSLog("BrownScreensaver: ERROR - video.mov not found in bundle")
            return
        }

        NSLog("BrownScreensaver: setupVideoPlayer()")
        teardownPlayer()

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
                if p.timeControlStatus == .paused {
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

        NSLog("BrownScreensaver: isReadyForDisplay + readyToPlay (isPreview=\(isPreview)) - starting playback")
        
        // Ensure audio is active
        p.isMuted = false
        p.volume = 1.0
        
        p.play()
        
        // Final check on rate/status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSLog("BrownScreensaver: Final check - rate=\(p.rate) status=\(p.timeControlStatus.rawValue) volume=\(p.volume) muted=\(p.isMuted)")
        }
    }

    // MARK: - Sleep / Wake / System Events

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleScreensSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreensWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Distributed Notifications: handle stop signals from the system more reliably than view lifecycle.
        // These fire immediately when the user dismisses the screensaver or unlocks.
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

    @objc private func handleScreensSleep() {
        NSLog("BrownScreensaver: screens sleep - pausing")
        player?.pause()
    }

    @objc private func handleScreensWake() {
        NSLog("BrownScreensaver: screens wake - scheduling recovery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.recoverPlayback()
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
            self?.recoverPlayback()
        }
    }

    /// Tears down and fully rebuilds the AV stack.
    /// This is the definitive fix for stall-after-time and post-sleep black screen.
    private func recoverPlayback() {
        NSLog("BrownScreensaver: recoverPlayback - rebuilding AV stack")
        isRecovering = false
        setupVideoPlayer()
        // Playback resumes automatically via observeValue once item + layer are ready.
    }

    // MARK: - Teardown

    private func teardownPlayer() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(
            self, name: AVPlayerItem.playbackStalledNotification, object: nil)
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

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerLooper = nil

        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    deinit {
        teardownPlayer()
        NSLog("BrownScreensaver: deinit")
    }

    // MARK: - ScreenSaverView Lifecycle

    public override func startAnimation() {
        super.startAnimation()
        NSLog("BrownScreensaver: startAnimation isPreview=\(isPreview)")
        
        // If we tore down the player in stopAnimation, rebuild it now
        if player == nil {
            NSLog("BrownScreensaver: Player is nil, rebuilding for startAnimation")
            setupVideoPlayer()
        }
        
        playIfReady()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        NSLog("BrownScreensaver: stopAnimation (isPreview=\(isPreview))")
        
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
