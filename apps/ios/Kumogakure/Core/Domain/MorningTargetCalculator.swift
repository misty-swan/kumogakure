import Foundation

/// Output of calculating the "Until tomorrow morning" preset duration and return timestamp.
struct MorningTargetResult: Equatable, Sendable {
    let durationMinutes: Int
    let plannedEndsAt: Date
    let wasClampedToMax: Bool
    let isNextDay: Bool
    let targetMinutesSinceMidnight: Int

    func returnSummary(timeZone: TimeZone = .current) -> String {
        let timeText = DurationFormatter.clockTimeString(plannedEndsAt, timeZone: timeZone)
        if wasClampedToMax {
            return "上限12時間：\(timeText) 頃帰還"
        }
        if isNextDay {
            return "翌 \(timeText) 頃帰還"
        }
        return "\(timeText) 頃帰還"
    }
}

/// Calculates duration for the "明日の朝まで" preset (OQ-16 / PRD FR-002).
enum MorningTargetCalculator {
    static func clampedTargetMinutes(_ rawMinutes: Int) -> Int {
        min(AppConfig.maxMorningTargetMinutes, max(AppConfig.minMorningTargetMinutes, rawMinutes))
    }

    static func calculate(
        now: Date,
        morningTargetMinutes: Int,
        calendar: Calendar = .current
    ) -> MorningTargetResult {
        let targetMinutes = clampedTargetMinutes(morningTargetMinutes)
        let startOfToday = calendar.startOfDay(for: now)
        let todayTarget = calendar.date(byAdding: .minute, value: targetMinutes, to: startOfToday) ?? now

        let minimumAllowedLeadTime = TimeInterval(AppConfig.minDurationMinutes * 60)
        let rawTargetDate: Date
        if now.addingTimeInterval(minimumAllowedLeadTime) <= todayTarget {
            rawTargetDate = todayTarget
        } else {
            rawTargetDate = calendar.date(byAdding: .day, value: 1, to: todayTarget)
                ?? todayTarget.addingTimeInterval(86_400)
        }

        let rawMinutes = Int(round(rawTargetDate.timeIntervalSince(now) / 60.0))
        let clampedMinutes = min(AppConfig.maxDurationMinutes, max(AppConfig.minDurationMinutes, rawMinutes))
        let plannedEndsAt = now.addingTimeInterval(TimeInterval(clampedMinutes * 60))
        let isNextDay = !calendar.isDate(plannedEndsAt, inSameDayAs: now)

        return MorningTargetResult(
            durationMinutes: clampedMinutes,
            plannedEndsAt: plannedEndsAt,
            wasClampedToMax: rawMinutes > AppConfig.maxDurationMinutes,
            isNextDay: isNextDay,
            targetMinutesSinceMidnight: targetMinutes
        )
    }
}
