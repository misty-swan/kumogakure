import SwiftUI

/// Grapheme-aware text sanitization and length clamping matching backend `sanitize.rs`.
enum TextInputLimiter {
    private static let forbiddenBidiScalars: Set<UInt32> = [
        0x061C, 0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    /// Strips forbidden control/bidi characters while keeping emoji ZWJ/variation sequences intact,
    /// then clamps to `limit` extended grapheme clusters.
    static func clampedGraphemes(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let filteredScalars = text.unicodeScalars.filter { scalar in
            if scalar.value == 0x200D || scalar.value == 0xFE0E || scalar.value == 0xFE0F {
                return true
            }
            if forbiddenBidiScalars.contains(scalar.value) {
                return false
            }
            if scalar == "\r" || scalar == "\n" || scalar == "\t" {
                return true
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }
            return true
        }
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
        return String(cleaned.prefix(limit))
    }

    /// Normalizes newlines/tabs to spaces, trims outer whitespace, and clamps to `limit` graphemes.
    static func sanitizedOptional(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let normalizedWhitespace = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let trimmed = normalizedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clamped = clampedGraphemes(trimmed, limit: limit)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clamped.isEmpty ? nil : clamped
    }
}

/// Palette definitions for absence cards aligned with `absence-card-spec.md` §2.1 & Rust `catalog.rs`.
struct AbsenceCardPalette: Sendable {
    let background: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let seal: Color
    let tagBackground: Color

    static func palette(for style: CardStyle) -> AbsenceCardPalette {
        switch style {
        case .washiClassic:
            return AbsenceCardPalette(
                background: Color(hex: 0xF4F0E6),
                border: Color(hex: 0xD6CFC2),
                primaryText: Color(hex: 0x1E2022),
                secondaryText: Color(hex: 0x5A5E63),
                seal: Color(hex: 0xB84A39),
                tagBackground: Color(hex: 0xE9E3D5)
            )
        case .sumiNight:
            return AbsenceCardPalette(
                background: Color(hex: 0x12151B),
                border: Color(hex: 0x2F3745),
                primaryText: Color(hex: 0xEAE6DF),
                secondaryText: Color(hex: 0x9CA3AE),
                seal: Color(hex: 0xC79A63),
                tagBackground: Color(hex: 0x1B2029)
            )
        case .indigoMist:
            return AbsenceCardPalette(
                background: Color(hex: 0x132230),
                border: Color(hex: 0x324A5F),
                primaryText: Color(hex: 0xECE9E2),
                secondaryText: Color(hex: 0xA2B3C2),
                seal: Color(hex: 0xC79A63),
                tagBackground: Color(hex: 0x1B3043)
            )
        }
    }
}

/// Output dimensions at `@1x` (`scale = 1.0`) matching `absence-card-spec.md` §3.1.
enum ShareCardFormat: String, CaseIterable, Identifiable, Sendable {
    case square
    case story

    var id: String { rawValue }

    var pixelSize: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .story: return CGSize(width: 1080, height: 1920)
        }
    }

    var aspectRatio: CGFloat {
        pixelSize.width / pixelSize.height
    }

    var outerVerticalPadding: CGFloat {
        switch self {
        case .square: return 44
        case .story: return 260
        }
    }

    var outerHorizontalPadding: CGFloat {
        44
    }
}

enum AbsenceCardMode: Equatable, Sendable {
    case activeAbsence(plannedEndsAt: Date, timeZone: TimeZone)
    case completedReturn(actualDurationSeconds: Int, completedAt: Date, timeZone: TimeZone)
}

struct AbsenceCardPayload: Equatable, Sendable {
    let theme: ThemeID
    let cardStyle: CardStyle
    let hideWatermark: Bool
    let displayName: String?
    let message: String?
    let mode: AbsenceCardMode

    init(
        theme: ThemeID,
        cardStyle: CardStyle,
        hideWatermark: Bool,
        displayName: String?,
        message: String?,
        mode: AbsenceCardMode
    ) {
        self.theme = theme
        self.cardStyle = cardStyle
        self.hideWatermark = hideWatermark
        self.displayName = TextInputLimiter.sanitizedOptional(
            displayName,
            limit: AppConfig.maxDisplayNameLength
        )
        self.message = TextInputLimiter.sanitizedOptional(
            message,
            limit: AppConfig.maxMessageLength
        )
        self.mode = mode
    }
}

/// Canonical 1080px-coordinate card view shared between S-02 live preview and `ImageRenderer`.
struct AbsenceCardSnapshotView: View {
    let payload: AbsenceCardPayload
    let format: ShareCardFormat

    private var palette: AbsenceCardPalette {
        AbsenceCardPalette.palette(for: payload.cardStyle)
    }

    private var headingText: String {
        switch payload.mode {
        case .activeAbsence:
            return "ただいま、雲隠れ中"
        case .completedReturn:
            return "雲隠れより、帰還しました"
        }
    }

    private var subtitleText: String {
        switch payload.mode {
        case .activeAbsence(let plannedEndsAt, let timeZone):
            let clock = DurationFormatter.clockTimeString(plannedEndsAt, timeZone: timeZone)
            let tzLabel = Self.shortTimeZoneLabel(timeZone)
            return "帰還予定：\(clock) 頃 (\(tzLabel))"
        case .completedReturn(let actualDurationSeconds, let completedAt, let timeZone):
            let duration = DurationFormatter.japaneseDuration(seconds: actualDurationSeconds)
            let clock = DurationFormatter.clockTimeString(completedAt, timeZone: timeZone)
            return "\(duration) の静寂を得ました（\(clock) 帰還）"
        }
    }

    private static func shortTimeZoneLabel(_ timeZone: TimeZone) -> String {
        if timeZone.identifier == "Asia/Tokyo" {
            return "JST"
        }
        return timeZone.abbreviation() ?? timeZone.identifier
    }

    var body: some View {
        let size = format.pixelSize

        ZStack {
            palette.background

            Image(payload.theme.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(payload.cardStyle == .washiClassic ? 0.11 : 0.16)

            RadialGradient(
                colors: [
                    palette.background.opacity(0.15),
                    palette.background.opacity(0.88),
                ],
                center: .center,
                startRadius: 120,
                endRadius: size.height * 0.65
            )

            outerCardFrame
                .padding(.horizontal, format.outerHorizontalPadding)
                .padding(.vertical, format.outerVerticalPadding)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var outerCardFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.background.opacity(0.82))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.border, lineWidth: 2.5)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border.opacity(0.75), lineWidth: 1.25)
                .padding(10)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                centerContent
                Spacer(minLength: 24)
                bottomBar
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 52)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(palette.secondaryText)
                Text("雲隠れ")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.seal, lineWidth: 3)
                    .frame(width: 68, height: 68)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.seal.opacity(0.65), lineWidth: 1)
                    .frame(width: 58, height: 58)
                Text("隠")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.seal)
            }
        }
    }

    private var centerContent: some View {
        VStack(spacing: 28) {
            Text(headingText)
                .font(.system(size: 56, weight: .medium, design: .serif))
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            Text(subtitleText)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)

            if let message = payload.message, !message.isEmpty {
                Text("「\(message)」")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(palette.primaryText.opacity(0.94))
                    .multilineTextAlignment(.center)
                    .lineSpacing(12)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
            }

            if let displayName = payload.displayName, !displayName.isEmpty {
                Text("── \(displayName) ──")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            Text(payload.theme.displayName)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(palette.tagBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(palette.border, lineWidth: 1)
                )

            Spacer()

            if !payload.hideWatermark {
                Text("雲隠れ - Kumogakure")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(palette.secondaryText.opacity(0.75))
            }
        }
    }
}
