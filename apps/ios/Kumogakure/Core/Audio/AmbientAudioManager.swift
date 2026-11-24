import AVFoundation
import Foundation

@MainActor
protocol AmbientAudioManaging: AnyObject {
    var currentSound: SoundID { get }
    var isPlaying: Bool { get }
    func play(sound: SoundID)
    func stopWithFadeOut()
    func stopImmediately()
    func playPreview(sound: SoundID)
    func stopPreview()
}

@MainActor
protocol AudioSessionManaging: AnyObject {
    func configurePlaybackCategory() throws
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws
}

@MainActor
protocol AudioPlayerControlling: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var isPlaying: Bool { get }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
    func setVolume(_ volume: Float, fadeDuration duration: TimeInterval)
}

@MainActor
final class AVAudioSessionAdapter: AudioSessionManaging {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func configurePlaybackCategory() throws {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    }

    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        let options: AVAudioSession.SetActiveOptions = notifyOthersOnDeactivation
            ? [.notifyOthersOnDeactivation]
            : []
        try session.setActive(active, options: options)
    }
}

@MainActor
final class AVAudioPlayerAdapter: AudioPlayerControlling {
    private let player: AVAudioPlayer

    init(url: URL) throws {
        self.player = try AVAudioPlayer(contentsOf: url)
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var numberOfLoops: Int {
        get { player.numberOfLoops }
        set { player.numberOfLoops = newValue }
    }

    var isPlaying: Bool { player.isPlaying }

    func prepareToPlay() -> Bool { player.prepareToPlay() }
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }

    func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
        player.setVolume(volume, fadeDuration: duration)
    }
}

/// Manages seamless ambient sound playback, 1.5s fade-out, interruptions, and 2.5.4 compliance.
@MainActor
final class AmbientAudioManager: AmbientAudioManaging {
    typealias PlayerFactory = @MainActor (URL) throws -> any AudioPlayerControlling
    typealias ResourceLocator = @MainActor (SoundID) -> URL?

    private let sessionManager: any AudioSessionManaging
    private let playerFactory: PlayerFactory
    private let resourceLocator: ResourceLocator
    private let scheduler: any TimerScheduling
    private let notificationCenter: NotificationCenter
    private let fadeOutDuration: TimeInterval
    private let previewDuration: TimeInterval

    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?

    private var player: (any AudioPlayerControlling)?
    private var fadeOutTask: (any CancellableTask)?
    private var previewTask: (any CancellableTask)?
    private var isSessionActive = false
    private var wasPausedByInterruption = false

    private(set) var currentSound: SoundID = .none
    private(set) var isPlaying = false

    init(
        sessionManager: any AudioSessionManaging = AVAudioSessionAdapter(),
        playerFactory: @escaping PlayerFactory = { try AVAudioPlayerAdapter(url: $0) },
        resourceLocator: @escaping ResourceLocator = AmbientAudioManager.defaultResourceLocator,
        scheduler: any TimerScheduling = AsyncTimerScheduler(),
        notificationCenter: NotificationCenter = .default,
        fadeOutDuration: TimeInterval = AppConfig.audioFadeOutDurationSeconds,
        previewDuration: TimeInterval = AppConfig.audioPreviewDurationSeconds
    ) {
        self.sessionManager = sessionManager
        self.playerFactory = playerFactory
        self.resourceLocator = resourceLocator
        self.scheduler = scheduler
        self.notificationCenter = notificationCenter
        self.fadeOutDuration = fadeOutDuration
        self.previewDuration = previewDuration

        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let info = Self.extractInterruptionInfo(from: notification)
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleAudioInterruption(began: info.began, shouldResume: info.shouldResume)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(began: info.began, shouldResume: info.shouldResume)
                }
            }
        }
    }

    deinit {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
        }
    }

    func play(sound: SoundID) {
        cancelPendingTasks()
        wasPausedByInterruption = false
        currentSound = sound

        // App Review 2.5.4: never activate AVAudioSession or play silent audio when `sound == .none`.
        guard sound != .none else {
            stopAndDeactivateIfNeeded()
            return
        }

        startPlayback(sound: sound, loops: -1)
    }

    func playPreview(sound: SoundID) {
        cancelPendingTasks()
        wasPausedByInterruption = false
        currentSound = sound

        guard sound != .none else {
            stopAndDeactivateIfNeeded()
            return
        }

        startPlayback(sound: sound, loops: 0)
        previewTask = scheduler.scheduleOnce(after: previewDuration) { [weak self] in
            self?.stopImmediately()
        }
    }

    func stopPreview() {
        guard previewTask != nil else { return }
        stopImmediately()
    }

    func stopWithFadeOut() {
        cancelPendingTasks()
        wasPausedByInterruption = false
        isPlaying = false

        guard let player else {
            deactivateSessionIfNeeded()
            return
        }

        player.setVolume(0, fadeDuration: fadeOutDuration)
        fadeOutTask = scheduler.scheduleOnce(after: fadeOutDuration) { [weak self] in
            self?.finishFadeOut()
        }
    }

    func stopImmediately() {
        cancelPendingTasks()
        wasPausedByInterruption = false
        stopAndDeactivateIfNeeded()
    }

    func handleAudioInterruption(began: Bool, shouldResume: Bool) {
        if began {
            guard isPlaying, let player else { return }
            player.pause()
            wasPausedByInterruption = true
            isPlaying = false
            return
        }

        guard wasPausedByInterruption else { return }
        wasPausedByInterruption = false
        guard shouldResume, currentSound != .none, let player else { return }

        do {
            try sessionManager.configurePlaybackCategory()
            try sessionManager.setActive(true, notifyOthersOnDeactivation: false)
            isSessionActive = true
            if player.play() {
                isPlaying = true
            }
        } catch {
            isPlaying = false
        }
    }

    // MARK: - Private

    private func startPlayback(sound: SoundID, loops: Int) {
        player?.stop()
        player = nil

        guard let url = resourceLocator(sound) else {
            isPlaying = false
            deactivateSessionIfNeeded()
            return
        }

        do {
            try sessionManager.configurePlaybackCategory()
            try sessionManager.setActive(true, notifyOthersOnDeactivation: false)
            isSessionActive = true

            let createdPlayer = try playerFactory(url)
            createdPlayer.numberOfLoops = loops
            createdPlayer.volume = 1.0
            _ = createdPlayer.prepareToPlay()
            if createdPlayer.play() {
                player = createdPlayer
                isPlaying = true
            } else {
                isPlaying = false
                deactivateSessionIfNeeded()
            }
        } catch {
            player = nil
            isPlaying = false
            deactivateSessionIfNeeded()
        }
    }

    private func finishFadeOut() {
        fadeOutTask = nil
        stopAndDeactivateIfNeeded()
    }

    private func stopAndDeactivateIfNeeded() {
        player?.stop()
        player = nil
        isPlaying = false
        deactivateSessionIfNeeded()
    }

    private func deactivateSessionIfNeeded() {
        guard isSessionActive else { return }
        try? sessionManager.setActive(false, notifyOthersOnDeactivation: true)
        isSessionActive = false
    }

    private func cancelPendingTasks() {
        fadeOutTask?.cancel()
        fadeOutTask = nil
        previewTask?.cancel()
        previewTask = nil
    }

    private static func defaultResourceLocator(_ sound: SoundID) -> URL? {
        guard let fileName = sound.resourceFileName else { return nil }
        if let rootURL = Bundle.main.url(
            forResource: fileName,
            withExtension: sound.resourceExtension
        ) {
            return rootURL
        }
        return Bundle.main.url(
            forResource: fileName,
            withExtension: sound.resourceExtension,
            subdirectory: "Sounds"
        )
    }

    private nonisolated static func extractInterruptionInfo(
        from notification: Notification
    ) -> (began: Bool, shouldResume: Bool) {
        let userInfo = notification.userInfo
        let rawType = (userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
        let interruptionType = rawType.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
        let began = (interruptionType == .began)

        let rawOptions = (userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
        let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        return (began: began, shouldResume: options.contains(.shouldResume))
    }
}
