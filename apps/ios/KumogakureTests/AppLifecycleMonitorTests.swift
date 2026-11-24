import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import Kumogakure

@MainActor
final class AppLifecycleMonitorTests: XCTestCase {
    private func makeSUT() -> (
        monitor: AppLifecycleMonitor,
        clock: MockClock,
        scheduler: ManualTestScheduler,
        bgManager: MockBackgroundTaskManager,
        center: NotificationCenter
    ) {
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let bgManager = MockBackgroundTaskManager()
        let center = NotificationCenter()
        let monitor = AppLifecycleMonitor(
            clock: clock,
            scheduler: scheduler,
            backgroundTaskManager: bgManager,
            notificationCenter: center
        )
        monitor.setMonitoringEnabled(true)
        return (monitor, clock, scheduler, bgManager, center)
    }

    func testInactivePhaseAloneDoesNotTriggerGraceOrInterrupt() {
        let sut = makeSUT()
        var graceEntered = 0
        var expired = 0
        sut.monitor.onEnterGracePeriod = { _ in graceEntered += 1 }
        sut.monitor.onGracePeriodExpired = { expired += 1 }

        sut.monitor.handleScenePhaseChange(.inactive)
        sut.scheduler.advance(by: 20)
        sut.monitor.handleScenePhaseChange(.active)

        XCTAssertEqual(graceEntered, 0)
        XCTAssertEqual(expired, 0)
        XCTAssertFalse(sut.monitor.isInGracePeriod)
    }

    func testScreenLockNotificationWithin0_2SecondsConfirmsLockAndKeepsActive() {
        let sut = makeSUT()
        var lockConfirmed = 0
        var graceEntered = 0
        var expired = 0
        var returnedWasLocked: Bool?

        sut.monitor.onScreenLockConfirmed = { lockConfirmed += 1 }
        sut.monitor.onEnterGracePeriod = { _ in graceEntered += 1 }
        sut.monitor.onGracePeriodExpired = { expired += 1 }
        sut.monitor.onReturnedActive = { returnedWasLocked = $0 }

        sut.monitor.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 0.2)

        #if canImport(UIKit)
        sut.center.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        #else
        sut.monitor.handleProtectedDataWillBecomeUnavailable()
        #endif

        sut.scheduler.advance(by: 30)

        XCTAssertEqual(lockConfirmed, 1)
        XCTAssertEqual(graceEntered, 0)
        XCTAssertEqual(expired, 0)
        XCTAssertTrue(sut.monitor.isScreenLockedInBackground)

        sut.monitor.handleScenePhaseChange(.inactive)
        sut.monitor.handleScenePhaseChange(.active)
        XCTAssertEqual(returnedWasLocked, true)
    }

    func testPrecedingScreenLockNotificationConfirmsLockImmediatelyOnBackground() {
        let sut = makeSUT()
        var lockConfirmed = 0
        var graceEntered = 0

        sut.monitor.onScreenLockConfirmed = { lockConfirmed += 1 }
        sut.monitor.onEnterGracePeriod = { _ in graceEntered += 1 }

        sut.monitor.handleScenePhaseChange(.inactive)
        sut.monitor.handleProtectedDataWillBecomeUnavailable()
        sut.scheduler.advance(by: 0.2)
        sut.monitor.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 15)

        XCTAssertEqual(lockConfirmed, 1)
        XCTAssertEqual(graceEntered, 0)
    }

    func testAppSwitchEntersGraceAfter1_5SecondsAndRecoversWithin9Seconds() {
        let sut = makeSUT()
        var graceDeadline: Date?
        var returnedWithinGrace = 0
        var expired = 0

        sut.monitor.onEnterGracePeriod = { graceDeadline = $0 }
        sut.monitor.onReturnWithinGracePeriod = { returnedWithinGrace += 1 }
        sut.monitor.onGracePeriodExpired = { expired += 1 }

        let t0 = sut.clock.now
        sut.monitor.handleScenePhaseChange(.background)

        sut.scheduler.advance(by: 1.4)
        XCTAssertNil(graceDeadline)

        sut.scheduler.advance(by: 0.2)
        XCTAssertNotNil(graceDeadline)
        XCTAssertEqual(graceDeadline!.timeIntervalSince(t0), 11.5, accuracy: 0.2)
        XCTAssertTrue(sut.monitor.isInGracePeriod)

        sut.scheduler.advance(by: 8.9)
        sut.monitor.handleScenePhaseChange(.inactive)
        sut.monitor.handleScenePhaseChange(.active)

        XCTAssertEqual(returnedWithinGrace, 1)
        XCTAssertEqual(expired, 0)
        XCTAssertFalse(sut.monitor.isInGracePeriod)
    }

    func testAppSwitchExceeding10SecondsExpiresGracePeriod() {
        let sut = makeSUT()
        var expired = 0
        sut.monitor.onGracePeriodExpired = { expired += 1 }

        sut.monitor.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 1.5)
        XCTAssertTrue(sut.monitor.isInGracePeriod)

        sut.scheduler.advance(by: 10.0)
        XCTAssertEqual(expired, 1)
        XCTAssertFalse(sut.monitor.isInGracePeriod)
    }

    func testSuspendedAppReturningAfterDeadlineTriggersGraceExpiryOnActive() {
        let sut = makeSUT()
        var expired = 0
        sut.monitor.onGracePeriodExpired = { expired += 1 }

        sut.monitor.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 1.5)
        XCTAssertTrue(sut.monitor.isInGracePeriod)

        // Simulate OS suspending background execution without firing graceExpiryTask, then returning at +11s.
        sut.clock.advance(by: 11.0)
        sut.monitor.handleScenePhaseChange(.active)

        XCTAssertEqual(expired, 1)
    }

    func testDisabledMonitoringIgnoresBackgroundTransitions() {
        let sut = makeSUT()
        sut.monitor.setMonitoringEnabled(false)

        var graceEntered = 0
        var expired = 0
        sut.monitor.onEnterGracePeriod = { _ in graceEntered += 1 }
        sut.monitor.onGracePeriodExpired = { expired += 1 }

        sut.monitor.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 20)

        XCTAssertEqual(graceEntered, 0)
        XCTAssertEqual(expired, 0)
    }
}
