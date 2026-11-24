import Foundation

/// Formatting helpers for countdown timers, Japanese durations, and 24-hour clock times.
enum DurationFormatter {
    static func countdownString(remainingSeconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(remainingSeconds)))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Minute-granularity label to keep VoiceOver from speaking every second.
    static func accessibilityRemainingText(remainingSeconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(remainingSeconds)))
        if clamped == 0 {
            return "残り時間 0分"
        }
        if clamped < 60 {
            return "残り時間 1分未満"
        }
        let totalMinutes = Int(ceil(Double(clamped) / 60.0))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return "残り時間 \(hours)時間\(minutes)分"
        } else if hours > 0 {
            return "残り時間 \(hours)時間"
        }
        return "残り時間 \(minutes)分"
    }

    static func japaneseDuration(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let mins = safeMinutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)時間\(mins)分"
        } else if hours > 0 {
            return "\(hours)時間"
        }
        return "\(mins)分"
    }

    static func japaneseDuration(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        if safeSeconds > 0 && minutes == 0 {
            return "\(safeSeconds)秒"
        }
        return japaneseDuration(minutes: minutes)
    }

    static func clockTimeString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func morningTargetString(minutesSinceMidnight: Int) -> String {
        let clamped = MorningTargetCalculator.clampedTargetMinutes(minutesSinceMidnight)
        let hours = clamped / 60
        let mins = clamped % 60
        return String(format: "%02d:%02d", hours, mins)
    }
}
