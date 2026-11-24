import SwiftData
import XCTest
@testable import Kumogakure

@MainActor
final class DetoxSessionStoreTests: XCTestCase {
    private struct SUT {
        let store: DetoxSessionStore
        let clock: MockClock
        let scheduler: ManualTestScheduler
        let audioManager: AmbientAudioManager
        let audioSession: MockAudioSession
        let notifications: MockNotificationScheduler
        let idleController: MockIdleTimerController
        let repository: SwiftDataSessionRepository
        let preferences: UserPreferencesStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeSUT() throws -> SUT {
        let suiteName = "app.kumogakure.store.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let preferences = UserPreferencesStore(defaults: defaults)
        let timerEngine = DetoxTimerEngine(clock: clock, scheduler: scheduler)
        let lifecycleMonitor = AppLifecycleMonitor(
            clock: clock,
            scheduler: scheduler,
            backgroundTaskManager: MockBackgroundTaskManager(),
            notificationCenter: NotificationCenter()
        )
        let audioSession = MockAudioSession()
        let audioManager = AmbientAudioManager(
            sessionManager: audioSession,
            playerFactory: { MockAudioPlayer(url: $0) },
            resourceLocator: { sound in
                sound.resourceFileName.map { URL(fileURLWithPath: "/tmp/\($0).m4a") }
            },
            scheduler: scheduler,
            notificationCenter: NotificationCenter()
        )
        let notifications = MockNotificationScheduler()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DetoxSessionRecord.self, configurations: configuration)
        let repository = SwiftDataSessionRepository(modelContext: container.mainContext)
        let idleController = MockIdleTimerController()

        let store = DetoxSessionStore(
            clock: clock,
            timerEngine: timerEngine,
            lifecycleMonitor: lifecycleMonitor,
            audioManager: audioManager,
            notificationScheduler: notifications,
            repository: repository,
            preferences: preferences,
            userIDProvider: KeychainHelper(store: InMemoryKeychainStore()),
            idleTimerController: idleController
        )

        return SUT(
            store: store,
            clock: clock,
            scheduler: scheduler,
            audioManager: audioManager,
            audioSession: audioSession,
            notifications: notifications,
            idleController: idleController,
            repository: repository,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func testQuietStartToCompletionAndIdleTimerReset() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.preferences.keepScreenOn = true
        sut.preferences.selectSound(.rain)

        sut.store.startSession(durationMinutes: 15, isPublic: false)

        XCTAssertEqual(sut.store.state, .active)
        XCTAssertTrue(sut.idleController.isIdleTimerDisabled)
        XCTAssertTrue(sut.audioManager.isPlaying)
        XCTAssertEqual(sut.notifications.scheduledCompletions.count, 1)

        sut.scheduler.advance(by: 900)

        guard case .completed(let summary) = sut.store.state else {
            return XCTFail("Expected completed state, got \(sut.store.state)")
        }
        XCTAssertEqual(summary.actualDurationSeconds, 900)
        XCTAssertFalse(sut.idleController.isIdleTimerDisabled)
        XCTAssertEqual(sut.store.cumulativeSummary.completedCount, 1)
        XCTAssertEqual(sut.store.cumulativeSummary.totalCompletedSeconds, 900)
        XCTAssertEqual(sut.notifications.canceledCompletions.count, 1)

        // Advance audio fade out duration (1.5s) and verify deactivation.
        sut.scheduler.advance(by: 1.5)
        XCTAssertFalse(sut.audioManager.isPlaying)
        XCTAssertEqual(sut.audioSession.setActiveCalls.last?.active, false)
    }

    func testScreenLockFollowedByTimeOverCompletesOnForegroundReturn() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.store.startSession(durationMinutes: 15, isPublic: false)

        sut.store.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 0.2)
        sut.store.lifecycleMonitor.handleProtectedDataWillBecomeUnavailable()

        XCTAssertTrue(sut.preferences.lastBackgroundWasScreenLock)
        sut.clock.advance(by: 1200)

        sut.store.handleScenePhaseChange(.active)

        guard case .completed(let summary) = sut.store.state else {
            return XCTFail("Expected completed state after screen lock over planned time, got \(sut.store.state)")
        }
        XCTAssertEqual(summary.actualDurationSeconds, 900)
        XCTAssertFalse(sut.preferences.lastBackgroundWasScreenLock)
    }

    func testGracePeriodExpiryTakesPrecedenceOverPlannedEndTime() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.store.startSession(durationMinutes: 15, isPublic: false)

        sut.store.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 1.5)
        guard case .gracePeriod = sut.store.state else {
            return XCTFail("Expected gracePeriod state")
        }
        XCTAssertEqual(sut.notifications.graceWarningScheduledCount, 1)

        // Both grace deadline (+10s) and planned end time (+15m) pass while suspended in another app.
        sut.clock.advance(by: 1000)
        sut.store.handleScenePhaseChange(.active)

        guard case .interrupted = sut.store.state else {
            return XCTFail("Expected interrupted state taking precedence, got \(sut.store.state)")
        }
    }

    func testEarlyCancelTransitionsToCanceledAndStopsIdleTimer() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.preferences.keepScreenOn = true
        sut.store.startSession(durationMinutes: 30, isPublic: false)

        sut.scheduler.advance(by: 180)
        sut.store.confirmEarlyCancel()

        guard case .canceled(let summary) = sut.store.state else {
            return XCTFail("Expected canceled state")
        }
        XCTAssertEqual(summary.actualDurationSeconds, 180)
        XCTAssertFalse(sut.idleController.isIdleTimerDisabled)
        XCTAssertEqual(sut.notifications.canceledCompletions.count, 1)
    }

    func testTaskKillRecoveryCompletedWhenPastPlannedEndAndActive() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let start = sut.clock.now.addingTimeInterval(-1800)
        let ends = sut.clock.now.addingTimeInterval(-60)
        let record = DetoxSessionRecord(
            plannedDurationSeconds: 1740,
            statusRaw: SessionStatus.active.rawValue,
            startedAt: start,
            plannedEndsAt: ends
        )
        try sut.repository.insert(record)
        try sut.repository.save()

        sut.store.recoverInProgressSessionIfNeeded()

        guard case .completed(let summary) = sut.store.state else {
            return XCTFail("Expected completed recovery")
        }
        XCTAssertEqual(summary.actualDurationSeconds, 1740)
        XCTAssertEqual(sut.store.cumulativeSummary.completedCount, 1)
    }

    func testTaskKillRecoveryResumesWhenScreenLockedAndWithinPlannedEnd() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let start = sut.clock.now.addingTimeInterval(-300)
        let ends = sut.clock.now.addingTimeInterval(600)
        let record = DetoxSessionRecord(
            plannedDurationSeconds: 900,
            statusRaw: SessionStatus.active.rawValue,
            startedAt: start,
            plannedEndsAt: ends
        )
        try sut.repository.insert(record)
        try sut.repository.save()
        sut.preferences.lastBackgroundWasScreenLock = true

        sut.store.recoverInProgressSessionIfNeeded()

        XCTAssertEqual(sut.store.state, .active)
        XCTAssertTrue(sut.store.timerEngine.isRunning)
        XCTAssertEqual(sut.store.timerEngine.remainingSeconds, 600, accuracy: 0.1)
    }

    func testTaskKillRecoveryInterruptsWhenNotScreenLocked() throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let start = sut.clock.now.addingTimeInterval(-300)
        let ends = sut.clock.now.addingTimeInterval(600)
        let record = DetoxSessionRecord(
            plannedDurationSeconds: 900,
            statusRaw: SessionStatus.active.rawValue,
            startedAt: start,
            plannedEndsAt: ends
        )
        try sut.repository.insert(record)
        try sut.repository.save()
        sut.preferences.lastBackgroundWasScreenLock = false

        sut.store.recoverInProgressSessionIfNeeded()

        guard case .interrupted(let summary) = sut.store.state else {
            return XCTFail("Expected interrupted recovery")
        }
        XCTAssertEqual(summary.actualDurationSeconds, 300)
    }
}
