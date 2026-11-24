import XCTest
@testable import Kumogakure

final class MorningTargetCalculatorTests: XCTestCase {
    private var tokyoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func makeJSTDate(year: Int = 2026, month: Int = 11, day: Int = 24, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: tokyoCalendar,
            timeZone: tokyoCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date!
    }

    func testLateNight2330TargetsNextMorning0700() {
        let now = makeJSTDate(hour: 23, minute: 30)
        let result = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 420,
            calendar: tokyoCalendar
        )

        XCTAssertEqual(result.durationMinutes, 450)
        XCTAssertFalse(result.wasClampedToMax)
        XCTAssertTrue(result.isNextDay)
        XCTAssertEqual(
            result.returnSummary(timeZone: tokyoCalendar.timeZone),
            "翌 07:00 頃帰還"
        )
    }

    func testAfternoon1500ClampsToMax12Hours() {
        let now = makeJSTDate(hour: 15, minute: 0)
        let result = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 420,
            calendar: tokyoCalendar
        )

        XCTAssertEqual(result.durationMinutes, 720)
        XCTAssertTrue(result.wasClampedToMax)
        XCTAssertTrue(result.isNextDay)
        XCTAssertEqual(
            result.returnSummary(timeZone: tokyoCalendar.timeZone),
            "上限12時間：03:00 頃帰還"
        )
    }

    func testExact15MinuteLeadTime0645TargetsSameMorning() {
        let now = makeJSTDate(hour: 6, minute: 45)
        let result = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 420,
            calendar: tokyoCalendar
        )

        XCTAssertEqual(result.durationMinutes, 15)
        XCTAssertFalse(result.wasClampedToMax)
        XCTAssertFalse(result.isNextDay)
        XCTAssertEqual(
            result.returnSummary(timeZone: tokyoCalendar.timeZone),
            "07:00 頃帰還"
        )
    }

    func testInside15MinuteThreshold0650TargetsNextMorningClampedTo12Hours() {
        let now = makeJSTDate(hour: 6, minute: 50)
        let result = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 420,
            calendar: tokyoCalendar
        )

        XCTAssertEqual(result.durationMinutes, 720)
        XCTAssertTrue(result.wasClampedToMax)
        XCTAssertFalse(result.isNextDay)
        XCTAssertEqual(
            result.returnSummary(timeZone: tokyoCalendar.timeZone),
            "上限12時間：18:50 頃帰還"
        )
    }

    func testEarlyMorning0200TargetsSameDay0700() {
        let now = makeJSTDate(hour: 2, minute: 0)
        let result = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 420,
            calendar: tokyoCalendar
        )

        XCTAssertEqual(result.durationMinutes, 300)
        XCTAssertFalse(result.wasClampedToMax)
        XCTAssertFalse(result.isNextDay)
        XCTAssertEqual(
            result.returnSummary(timeZone: tokyoCalendar.timeZone),
            "07:00 頃帰還"
        )
    }

    func testMorningTargetClampingAndCustomTime0530() {
        let now = makeJSTDate(hour: 23, minute: 30)
        let customResult = MorningTargetCalculator.calculate(
            now: now,
            morningTargetMinutes: 330, // 05:30
            calendar: tokyoCalendar
        )
        XCTAssertEqual(customResult.durationMinutes, 360)
        XCTAssertEqual(customResult.returnSummary(timeZone: tokyoCalendar.timeZone), "翌 05:30 頃帰還")

        XCTAssertEqual(MorningTargetCalculator.clampedTargetMinutes(240), 300)
        XCTAssertEqual(MorningTargetCalculator.clampedTargetMinutes(700), 600)
    }
}
