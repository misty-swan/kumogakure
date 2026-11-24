import SwiftUI

/// Typography hierarchy using system Serif (Hiragino Mincho ProN) and standard Sans.
enum KumogakureTypography {
    static let appTitle: Font = .system(.title2, design: .serif, weight: .medium)
    static let heroTitle: Font = .system(.largeTitle, design: .serif, weight: .regular)
    static let sectionHeading: Font = .system(.headline, design: .serif, weight: .medium)
    static let timerDisplay: Font = .system(size: 56, weight: .ultraLight, design: .serif).monospacedDigit()
    static let body: Font = .system(.body, design: .default)
    static let subheadline: Font = .system(.subheadline, design: .default)
    static let caption: Font = .system(.caption, design: .default)
    static let chipLabel: Font = .system(.subheadline, design: .default, weight: .medium)
}
