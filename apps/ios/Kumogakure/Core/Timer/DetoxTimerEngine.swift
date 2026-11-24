import Foundation
import Observation

/// Absolute-time countdown engine computing `remainingSeconds` and `progress` from `plannedEndsAt` (`Date`).
@Observable
@MainActor
final class DetoxTimerEngine {
    private let clock: any ClockProviding
    private let scheduler: any TimerScheduling

    private var tickTask: (any CancellableTask)?
    private var hasFiredCompletion = false

    private(set) var startedAt: Date?
    private(set) var plannedEndsAt: Date?
    private(set) var remainingSeconds: TimeInterval = 0
    private(set) var progress: Double = 0
    private(set) var isRunning: Bool = false

    var onCompleted: (() -> Void)?

    init(
        clock: any ClockProviding = SystemClock(),
        scheduler: any TimerScheduling = AsyncTimerScheduler()
    ) {
        self.clock = clock
        self.scheduler = scheduler
    }

    func start(startedAt: Date, plannedEndsAt: Date) {
        stop()
        self.startedAt = startedAt
        self.plannedEndsAt = plannedEndsAt
        self.hasFiredCompletion = false
        self.isRunning = true

        refresh()
        guard isRunning else { return }

        tickTask = scheduler.scheduleRepeating(interval: 1.0) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        guard let startedAt, let plannedEndsAt else { return }
        let now = clock.now
        let total = max(1.0, plannedEndsAt.timeIntervalSince(startedAt))
        let elapsed = max(0.0, now.timeIntervalSince(startedAt))
        let remaining = max(0.0, plannedEndsAt.timeIntervalSince(now))

        remainingSeconds = remaining
        progress = min(1.0, max(0.0, elapsed / total))

        if remaining <= 0 {
            stop()
            if !hasFiredCompletion {
                hasFiredCompletion = true
                onCompleted?()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
    }

    func reset() {
        stop()
        startedAt = nil
        plannedEndsAt = nil
        remainingSeconds = 0
        progress = 0
        hasFiredCompletion = false
    }
}
