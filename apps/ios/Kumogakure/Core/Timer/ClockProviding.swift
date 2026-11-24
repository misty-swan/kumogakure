import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Injectable clock for deterministic time-based tests.
protocol ClockProviding: Sendable {
    var now: Date { get }
}

struct SystemClock: ClockProviding {
    var now: Date { Date() }
}

/// Handle for cancelling scheduled timers or delayed callbacks.
@MainActor
protocol CancellableTask: AnyObject {
    func cancel()
}

/// Injectable timer scheduler for 1-second timer updates and delayed lifecycle checks.
@MainActor
protocol TimerScheduling: AnyObject {
    func scheduleOnce(
        after seconds: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask

    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask
}

@MainActor
private final class SwiftTaskHandle: CancellableTask {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class AsyncTimerScheduler: TimerScheduling {
    func scheduleOnce(
        after seconds: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let clamped = max(0, seconds)
        let task = Task { @MainActor in
            let nanoseconds = UInt64(clamped * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            action()
        }
        return SwiftTaskHandle(task: task)
    }

    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let clamped = max(0.05, interval)
        let task = Task { @MainActor in
            let nanoseconds = UInt64(clamped * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { break }
                action()
            }
        }
        return SwiftTaskHandle(task: task)
    }
}

/// Controls screen idle timer (`isIdleTimerDisabled`).
@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

@MainActor
final class UIApplicationIdleTimerController: IdleTimerControlling {
    var isIdleTimerDisabled: Bool {
        get {
            #if canImport(UIKit)
            return UIApplication.shared.isIdleTimerDisabled
            #else
            return false
            #endif
        }
        set {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = newValue
            #endif
        }
    }
}

/// Manages iOS short-lived background execution tasks during the 10-second grace window.
@MainActor
protocol BackgroundTaskManaging: AnyObject {
    func beginBackgroundTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> Int
    func endBackgroundTask(_ identifier: Int)
}

@MainActor
final class UIApplicationBackgroundTaskManager: BackgroundTaskManaging {
    func beginBackgroundTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> Int {
        #if canImport(UIKit)
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in
                expirationHandler()
            }
        }
        return identifier.rawValue
        #else
        return 0
        #endif
    }

    func endBackgroundTask(_ identifier: Int) {
        #if canImport(UIKit)
        let taskID = UIBackgroundTaskIdentifier(rawValue: identifier)
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        #endif
    }
}
