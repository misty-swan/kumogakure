import Foundation

struct WeekdayStat: Identifiable, Equatable, Sendable {
    let id: Int // Calendar weekday (1 = Sun ... 7 = Sat)
    let label: String
    let totalMinutes: Int
    let sessionCount: Int
}

enum TimeBand: String, CaseIterable, Identifiable, Sendable {
    case earlyMorning
    case daytime
    case evening
    case lateNight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .earlyMorning: return "早朝"
        case .daytime: return "日中"
        case .evening: return "夜"
        case .lateNight: return "深夜"
        }
    }

    var rangeHint: String {
        switch self {
        case .earlyMorning: return "5-9時"
        case .daytime: return "9-17時"
        case .evening: return "17-23時"
        case .lateNight: return "23-5時"
        }
    }

    static func band(forHour hour: Int) -> TimeBand {
        switch hour {
        case 5..<9: return .earlyMorning
        case 9..<17: return .daytime
        case 17..<23: return .evening
        default: return .lateNight
        }
    }
}

struct TimeBandStat: Identifiable, Equatable, Sendable {
    let band: TimeBand
    let totalMinutes: Int
    let sessionCount: Int

    var id: String { band.id }
}

struct HistoryAnalyticsSummary: Equatable, Sendable {
    let weekdayStats: [WeekdayStat]
    let timeBandStats: [TimeBandStat]
    let totalCompletedCount: Int
    let totalCompletedMinutes: Int
}

/// Aggregates completed sessions by weekday (Mon-Sun) and time of day for S-06 Swift Charts.
enum HistoryAnalytics {
    private static let weekdayOrder: [(id: Int, label: String)] = [
        (2, "月"),
        (3, "火"),
        (4, "水"),
        (5, "木"),
        (6, "金"),
        (7, "土"),
        (1, "日"),
    ]

    static func summarize(
        records: [DetoxSessionRecord],
        calendar: Calendar = .current
    ) -> HistoryAnalyticsSummary {
        let completedRecords = records.filter { $0.status == .completed }

        var weekdayMinutes: [Int: Int] = [:]
        var weekdayCounts: [Int: Int] = [:]
        var bandMinutes: [TimeBand: Int] = [:]
        var bandCounts: [TimeBand: Int] = [:]

        var totalMinutes = 0
        for record in completedRecords {
            let minutes = max(0, record.actualDurationSeconds) / 60
            totalMinutes += minutes

            let weekday = calendar.component(.weekday, from: record.startedAt)
            weekdayMinutes[weekday, default: 0] += minutes
            weekdayCounts[weekday, default: 0] += 1

            let hour = calendar.component(.hour, from: record.startedAt)
            let band = TimeBand.band(forHour: hour)
            bandMinutes[band, default: 0] += minutes
            bandCounts[band, default: 0] += 1
        }

        let weekdayStats = weekdayOrder.map { entry in
            WeekdayStat(
                id: entry.id,
                label: entry.label,
                totalMinutes: weekdayMinutes[entry.id, default: 0],
                sessionCount: weekdayCounts[entry.id, default: 0]
            )
        }

        let timeBandStats = TimeBand.allCases.map { band in
            TimeBandStat(
                band: band,
                totalMinutes: bandMinutes[band, default: 0],
                sessionCount: bandCounts[band, default: 0]
            )
        }

        return HistoryAnalyticsSummary(
            weekdayStats: weekdayStats,
            timeBandStats: timeBandStats,
            totalCompletedCount: completedRecords.count,
            totalCompletedMinutes: totalMinutes
        )
    }
}
