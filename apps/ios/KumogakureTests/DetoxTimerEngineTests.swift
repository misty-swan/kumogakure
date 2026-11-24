import XCTest
@testable import Kumogakure

@MainActor
final class DetoxTimerEngineTests: XCTestCase {
    func testAbsoluteTimeProgressAndCompletion15Minutes() {
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let engine = DetoxTimerEngine(clock: clock, scheduler: scheduler)

        var completionCount = 0
        engine.onCompleted = { completionCount += 1 }

        let start = clock.now
        let ends = start.addingTimeInterval(900)
        engine.start(startedAt: start, plannedEndsAt: ends)

        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.remainingSeconds, 900, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 0.0, accuracy: 0.001)

        scheduler.advance(by: 450)
        XCTAssertEqual(engine.remainingSeconds, 450, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(completionCount, 0)

        scheduler.advance(by: 450)
        XCTAssertEqual(engine.remainingSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 1.0, accuracy: 0.001)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(completionCount, 1)

        scheduler.advance(by: 10)
        XCTAssertEqual(completionCount, 1)
    }

    func testMaxDuration12HoursTracking() {
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let engine = DetoxTimerEngine(clock: clock, scheduler: scheduler)

        var completionCount = 0
        engine.onCompleted = { completionCount += 1 }

        let start = clock.now
        let ends = start.addingTimeInterval(43_200)
        engine.start(startedAt: start, plannedEndsAt: ends)

        clock.advance(by: 21_600)
        engine.refresh()
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(engine.remainingSeconds, 21_600, accuracy: 0.001)
        XCTAssertEqual(completionCount, 0)

        clock.advance(by: 21_600)
        engine.refresh()
        XCTAssertEqual(engine.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(completionCount, 1)
    }

    func testFogVisualMetricsInterpolationBoundaries() {
        let start = FogVisualMetrics(progress: 0.0)
        XCTAssertEqual(start.backgroundBlurRadius, 16.0, accuracy: 0.001)
        XCTAssertEqual(start.backgroundBrightness, -0.25, accuracy: 0.001)
        XCTAssertEqual(start.farFogOpacity, 0.72, accuracy: 0.001)
        XCTAssertEqual(start.nearFogOpacity, 0.85, accuracy: 0.001)

        let mid = FogVisualMetrics(progress: 0.5)
        XCTAssertEqual(mid.backgroundBlurRadius, 6.0, accuracy: 0.001)
        XCTAssertEqual(mid.backgroundBrightness, -0.10, accuracy: 0.001)
        XCTAssertEqual(mid.farFogOpacity, 0.35, accuracy: 0.001)
        XCTAssertEqual(mid.nearFogOpacity, 0.40, accuracy: 0.001)

        let end = FogVisualMetrics(progress: 1.0)
        XCTAssertEqual(end.backgroundBlurRadius, 0.0, accuracy: 0.001)
        XCTAssertEqual(end.backgroundBrightness, 0.0, accuracy: 0.001)
        XCTAssertEqual(end.farFogOpacity, 0.0, accuracy: 0.001)
        XCTAssertEqual(end.nearFogOpacity, 0.0, accuracy: 0.001)
    }

    func testDurationFormatterOutputs() {
        XCTAssertEqual(DurationFormatter.countdownString(remainingSeconds: 0), "00:00")
        XCTAssertEqual(DurationFormatter.countdownString(remainingSeconds: 1499.2), "25:00")
        XCTAssertEqual(DurationFormatter.countdownString(remainingSeconds: 3661), "01:01:01")

        XCTAssertEqual(DurationFormatter.accessibilityRemainingText(remainingSeconds: 45), "残り時間 1分未満")
        XCTAssertEqual(DurationFormatter.accessibilityRemainingText(remainingSeconds: 1500), "残り時間 25分")
        XCTAssertEqual(DurationFormatter.accessibilityRemainingText(remainingSeconds: 4800), "残り時間 1時間20分")

        XCTAssertEqual(DurationFormatter.japaneseDuration(minutes: 90), "1時間30分")
        XCTAssertEqual(DurationFormatter.morningTargetString(minutesSinceMidnight: 420), "07:00")
    }
}
