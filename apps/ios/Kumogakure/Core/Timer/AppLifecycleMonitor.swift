import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Platform-independent scene phase wrapper for testable lifecycle logic.
enum AppScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

/// Distinguishes device screen lock from switching to another app (ADR-002 / ios-app-spec.md §3.2).
@MainActor
final class AppLifecycleMonitor {
    private let clock: any ClockProviding
    private let scheduler: any TimerScheduling
    private let backgroundTaskManager: any BackgroundTaskManaging
    private let notificationCenter: NotificationCenter
    private let lockDetectionDelay: TimeInterval
    private let gracePeriodDuration: TimeInterval

    private nonisolated(unsafe) var protectedDataObserver: NSObjectProtocol?

    private var lockDetectionTask: (any CancellableTask)?
    private var graceExpiryTask: (any CancellableTask)?
    private var activeBackgroundTaskID: Int?
    private var lastProtectedDataUnavailableAt: Date?

    private(set) var isMonitoringEnabled = false
    private(set) var currentPhase: AppScenePhase = .active
    private(set) var isInGracePeriod = false
    private(set) var graceDeadline: Date?
    private(set) var isScreenLockedInBackground = false

    var onScreenLockConfirmed: (() -> Void)?
    var onEnterGracePeriod: ((Date) -> Void)?
    var onReturnWithinGracePeriod: (() -> Void)?
    var onGracePeriodExpired: (() -> Void)?
    var onReturnedActive: ((Bool) -> Void)?

    init(
        clock: any ClockProviding = SystemClock(),
        scheduler: any TimerScheduling = AsyncTimerScheduler(),
        backgroundTaskManager: any BackgroundTaskManaging = UIApplicationBackgroundTaskManager(),
        notificationCenter: NotificationCenter = .default,
        lockDetectionDelay: TimeInterval = AppConfig.lockDetectionDelaySeconds,
        gracePeriodDuration: TimeInterval = AppConfig.gracePeriodDurationSeconds
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.backgroundTaskManager = backgroundTaskManager
        self.notificationCenter = notificationCenter
        self.lockDetectionDelay = lockDetectionDelay
        self.gracePeriodDuration = gracePeriodDuration

        #if canImport(UIKit)
        protectedDataObserver = notificationCenter.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleProtectedDataWillBecomeUnavailable()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleProtectedDataWillBecomeUnavailable()
                }
            }
        }
        #endif
    }

    deinit {
        if let protectedDataObserver {
            notificationCenter.removeObserver(protectedDataObserver)
        }
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        isMonitoringEnabled = enabled
        if !enabled {
            cancelScheduledTasks()
            endActiveBackgroundTask()
            isInGracePeriod = false
            graceDeadline = nil
            isScreenLockedInBackground = false
            lastProtectedDataUnavailableAt = nil
        }
    }

    func handleScenePhaseChange(_ newPhase: AppScenePhase) {
        guard newPhase != currentPhase else { return }
        currentPhase = newPhase

        guard isMonitoringEnabled else { return }

        switch newPhase {
        case .inactive:
            // Ignore `.inactive` alone (notification center, control center, incoming call sheet).
            break

        case .background:
            beginBackgroundTransition()

        case .active:
            handleReturnedToForeground()
        }
    }

    func handleProtectedDataWillBecomeUnavailable() {
        guard isMonitoringEnabled else { return }
        lastProtectedDataUnavailableAt = clock.now

        if currentPhase == .background && !isInGracePeriod && !isScreenLockedInBackground {
            confirmScreenLock()
        }
    }

    private func beginBackgroundTransition() {
        isScreenLockedInBackground = false
        cancelScheduledTasks()

        if let lockedAt = lastProtectedDataUnavailableAt,
           clock.now.timeIntervalSince(lockedAt) <= 2.0 {
            confirmScreenLock()
            return
        }

        beginBackgroundTaskIfNeeded()
        lockDetectionTask = scheduler.scheduleOnce(after: lockDetectionDelay) { [weak self] in
            self?.enterGracePeriod()
        }
    }

    private func confirmScreenLock() {
        lockDetectionTask?.cancel()
        lockDetectionTask = nil
        endActiveBackgroundTask()
        isScreenLockedInBackground = true
        onScreenLockConfirmed?()
    }

    private func enterGracePeriod() {
        guard isMonitoringEnabled, currentPhase == .background, !isScreenLockedInBackground else {
            return
        }
        lockDetectionTask = nil
        isInGracePeriod = true
        let deadline = clock.now.addingTimeInterval(gracePeriodDuration)
        graceDeadline = deadline
        onEnterGracePeriod?(deadline)

        graceExpiryTask = scheduler.scheduleOnce(after: gracePeriodDuration) { [weak self] in
            self?.handleGracePeriodTimeout()
        }
    }

    private func handleGracePeriodTimeout() {
        guard isMonitoringEnabled, isInGracePeriod else { return }
        cancelScheduledTasks()
        endActiveBackgroundTask()
        isInGracePeriod = false
        graceDeadline = nil
        isScreenLockedInBackground = false
        onGracePeriodExpired?()
    }

    private func handleReturnedToForeground() {
        cancelScheduledTasks()
        endActiveBackgroundTask()
        lastProtectedDataUnavailableAt = nil

        if isInGracePeriod {
            let deadline = graceDeadline ?? clock.now
            isInGracePeriod = false
            graceDeadline = nil
            isScreenLockedInBackground = false
            if clock.now >= deadline {
                onGracePeriodExpired?()
            } else {
                onReturnWithinGracePeriod?()
            }
            return
        }

        let wasScreenLocked = isScreenLockedInBackground
        isScreenLockedInBackground = false
        onReturnedActive?(wasScreenLocked)
    }

    private func beginBackgroundTaskIfNeeded() {
        guard activeBackgroundTaskID == nil else { return }
        let identifier = backgroundTaskManager.beginBackgroundTask(
            name: "app.kumogakure.gracePeriod"
        ) { [weak self] in
            self?.endActiveBackgroundTask()
        }
        activeBackgroundTaskID = identifier
    }

    private func endActiveBackgroundTask() {
        if let identifier = activeBackgroundTaskID {
            activeBackgroundTaskID = nil
            backgroundTaskManager.endBackgroundTask(identifier)
        }
    }

    private func cancelScheduledTasks() {
        lockDetectionTask?.cancel()
        lockDetectionTask = nil
        graceExpiryTask?.cancel()
        graceExpiryTask = nil
    }
}
