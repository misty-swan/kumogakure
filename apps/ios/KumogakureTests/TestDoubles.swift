import Foundation
import UserNotifications
@testable import Kumogakure

final class MockClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date = Date(timeIntervalSince1970: 1_795_150_000)) {
        self.current = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func setNow(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@MainActor
final class ManualTestScheduler: TimerScheduling {
    private final class ScheduledItem: CancellableTask {
        let id: UUID
        var fireAt: Date
        let interval: TimeInterval?
        let action: @MainActor () -> Void
        var isCancelled = false

        init(
            id: UUID = UUID(),
            fireAt: Date,
            interval: TimeInterval?,
            action: @escaping @MainActor () -> Void
        ) {
            self.id = id
            self.fireAt = fireAt
            self.interval = interval
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private let clock: MockClock
    private var items: [ScheduledItem] = []

    init(clock: MockClock) {
        self.clock = clock
    }

    func scheduleOnce(
        after seconds: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let item = ScheduledItem(
            fireAt: clock.now.addingTimeInterval(max(0, seconds)),
            interval: nil,
            action: action
        )
        items.append(item)
        return item
    }

    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let safeInterval = max(0.05, interval)
        let item = ScheduledItem(
            fireAt: clock.now.addingTimeInterval(safeInterval),
            interval: safeInterval,
            action: action
        )
        items.append(item)
        return item
    }

    /// Advances `clock` by `seconds`, firing due one-shot and repeating timers in chronological order.
    func advance(by seconds: TimeInterval) {
        let target = clock.now.addingTimeInterval(max(0, seconds))
        while true {
            items.removeAll { $0.isCancelled }
            guard let next = items
                .filter({ $0.fireAt <= target })
                .min(by: { $0.fireAt < $1.fireAt })
            else {
                break
            }

            if next.fireAt > clock.now {
                clock.setNow(next.fireAt)
            }

            if let interval = next.interval {
                next.fireAt = next.fireAt.addingTimeInterval(interval)
            } else {
                items.removeAll { $0.id == next.id }
            }

            if !next.isCancelled {
                next.action()
            }
        }

        if target > clock.now {
            clock.setNow(target)
        }
    }
}

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func readString(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    func writeString(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[account] = value
        return true
    }

    func deleteValue(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
        return true
    }
}

@MainActor
final class MockAudioSession: AudioSessionManaging {
    struct SetActiveCall: Equatable {
        let active: Bool
        let notifyOthers: Bool
    }

    private(set) var configureCount = 0
    private(set) var setActiveCalls: [SetActiveCall] = []
    var shouldThrowOnActivate = false

    func configurePlaybackCategory() throws {
        configureCount += 1
    }

    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        if shouldThrowOnActivate && active {
            throw NSError(domain: "MockAudioSession", code: -1)
        }
        setActiveCalls.append(SetActiveCall(active: active, notifyOthers: notifyOthersOnDeactivation))
    }
}

@MainActor
final class MockAudioPlayer: AudioPlayerControlling {
    let url: URL
    var volume: Float = 1.0
    var numberOfLoops: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var fadeOutCalls: [(volume: Float, duration: TimeInterval)] = []

    init(url: URL) {
        self.url = url
    }

    func prepareToPlay() -> Bool {
        prepareCount += 1
        return true
    }

    func play() -> Bool {
        playCount += 1
        isPlaying = true
        return true
    }

    func pause() {
        pauseCount += 1
        isPlaying = false
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }

    func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
        self.volume = volume
        fadeOutCalls.append((volume: volume, duration: duration))
    }
}

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    private(set) var requestAuthorizationCount = 0
    var authorizationGrantResult = true
    private(set) var scheduledCompletions: [(sessionID: UUID, endsAt: Date)] = []
    private(set) var canceledCompletions: [UUID] = []
    private(set) var graceWarningScheduledCount = 0
    private(set) var graceWarningCanceledCount = 0

    func requestAuthorizationIfNeeded() async -> Bool {
        requestAuthorizationCount += 1
        return authorizationGrantResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationGrantResult ? .authorized : .denied
    }

    func scheduleCompletionNotification(sessionID: UUID, endsAt: Date) {
        scheduledCompletions.append((sessionID: sessionID, endsAt: endsAt))
    }

    func cancelCompletionNotification(sessionID: UUID) {
        canceledCompletions.append(sessionID)
    }

    func scheduleGraceWarningNotification() {
        graceWarningScheduledCount += 1
    }

    func cancelGraceWarningNotification() {
        graceWarningCanceledCount += 1
    }
}

@MainActor
final class MockIdleTimerController: IdleTimerControlling {
    var isIdleTimerDisabled: Bool = false {
        didSet {
            history.append(isIdleTimerDisabled)
        }
    }
    private(set) var history: [Bool] = []
}

@MainActor
final class MockBackgroundTaskManager: BackgroundTaskManaging {
    private var nextID = 100
    private(set) var beganTaskNames: [String] = []
    private(set) var endedTaskIDs: [Int] = []

    func beginBackgroundTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> Int {
        beganTaskNames.append(name)
        nextID += 1
        return nextID
    }

    func endBackgroundTask(_ identifier: Int) {
        endedTaskIDs.append(identifier)
    }
}
