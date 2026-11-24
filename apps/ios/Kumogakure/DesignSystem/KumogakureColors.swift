import SwiftUI

/// Canonical color palette defined in `docs/02-design/design-system.md`.
enum KumogakureColors {
    static let sumiBg = Color(hex: 0x0F1216)
    static let yonagaSurface = Color(hex: 0x181D24)
    static let mistBorder = Color(hex: 0x2B333F)
    static let washiText = Color(hex: 0xEAE6DF)
    static let usuzumiText = Color(hex: 0x9CA3AE)
    static let shinonomeAccent = Color(hex: 0xC79A63)
    static let shuinAccent = Color(hex: 0xB84A39)
    static let asagiInfo = Color(hex: 0x5C8D89)
    static let washiCardBg = Color(hex: 0xF4F0E6)
    static let sumiInk = Color(hex: 0x1E2022)
    static let fogOverlayTint = Color(hex: 0xD8DEE6)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
