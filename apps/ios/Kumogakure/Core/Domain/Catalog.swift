import Foundation

/// Canonical landscape themes matching backend catalog and Assets.xcassets.
enum ThemeID: String, CaseIterable, Identifiable, Codable, Sendable {
    case mistyMountain = "misty_mountain"
    case rainyBamboo = "rainy_bamboo"
    case moonlitLake = "moonlit_lake"
    case dawnShrine = "dawn_shrine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mistyMountain: return "霧の山並み"
        case .rainyBamboo: return "雨の竹林"
        case .moonlitLake: return "月夜の湖畔"
        case .dawnShrine: return "夜明けの社"
        }
    }

    var subtitle: String {
        switch self {
        case .mistyMountain: return "朝霧に沈む静かな連峰"
        case .rainyBamboo: return "しっとりと濡れる竹の小径"
        case .moonlitLake: return "満月を映す静謐な湖面"
        case .dawnShrine: return "東雲色に染まる山社"
        }
    }

    var isPro: Bool {
        switch self {
        case .mistyMountain, .rainyBamboo: return false
        case .moonlitLake, .dawnShrine: return true
        }
    }

    /// Image asset name in Assets.xcassets (Landscapes group has provides-namespace = false).
    var assetName: String { rawValue }

    static func resolved(rawValue: String, isPro: Bool) -> ThemeID {
        let parsed = ThemeID(rawValue: rawValue) ?? .mistyMountain
        if parsed.isPro && !isPro {
            return .mistyMountain
        }
        return parsed
    }
}

/// Canonical ambient sounds (`none` disables AVAudioSession activation completely).
enum SoundID: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "none"
    case rain = "rain"
    case nightWind = "night_wind"
    case bonfire = "bonfire"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "無音"
        case .rain: return "雨音"
        case .nightWind: return "夜風"
        case .bonfire: return "焚き火"
        }
    }

    var isPro: Bool {
        self == .bonfire
    }

    var resourceFileName: String? {
        switch self {
        case .none: return nil
        case .rain: return "rain"
        case .nightWind: return "night_wind"
        case .bonfire: return "bonfire"
        }
    }

    var resourceExtension: String { "m4a" }

    var sfSymbol: String {
        switch self {
        case .none: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .nightWind: return "wind"
        case .bonfire: return "flame"
        }
    }

    static func resolved(rawValue: String, isPro: Bool) -> SoundID {
        let parsed = SoundID(rawValue: rawValue) ?? .rain
        if parsed.isPro && !isPro {
            return .rain
        }
        return parsed
    }
}

/// Canonical absence card visual themes matching backend `CardStyle`.
enum CardStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case washiClassic = "washi_classic"
    case sumiNight = "sumi_night"
    case indigoMist = "indigo_mist"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .washiClassic: return "和紙"
        case .sumiNight: return "墨夜"
        case .indigoMist: return "藍霧"
        }
    }

    var isPro: Bool {
        self != .washiClassic
    }

    static func resolved(rawValue: String, isPro: Bool) -> CardStyle {
        let parsed = CardStyle(rawValue: rawValue) ?? .washiClassic
        if parsed.isPro && !isPro {
            return .washiClassic
        }
        return parsed
    }
}

/// Canonical session purpose presets and preset messages aligned with backend `PRESET_MESSAGES`.
enum PurposeID: String, CaseIterable, Identifiable, Codable, Sendable {
    case rest = "rest"
    case reading = "reading"
    case sleep = "sleep"
    case focus = "focus"
    case walk = "walk"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rest: return "ただ休む"
        case .reading: return "読書"
        case .sleep: return "睡眠"
        case .focus: return "集中・作業"
        case .walk: return "散歩・入浴"
        case .custom: return "自由に入力"
        }
    }

    /// Exact match for backend `PRESET_MESSAGES` in `services/api/src/domain/catalog.rs`.
    var presetMessage: String? {
        switch self {
        case .rest: return "少しの間、ひと休みします"
        case .reading: return "読書してきます"
        case .sleep: return "おやすみなさい。朝まで雲隠れします"
        case .focus: return "集中して作業してきます"
        case .walk: return "少し散歩・入浴してきます"
        case .custom: return nil
        }
    }

    var isPro: Bool {
        self == .custom
    }

    static func resolved(rawValue: String, isPro: Bool) -> PurposeID {
        let parsed = PurposeID(rawValue: rawValue) ?? .rest
        if parsed.isPro && !isPro {
            return .rest
        }
        return parsed
    }
}

/// Persisted and runtime session lifecycle status.
enum SessionStatus: String, Codable, Sendable, Equatable {
    case active = "active"
    case gracePeriod = "gracePeriod"
    case completed = "completed"
    case canceled = "canceled"
    case interrupted = "interrupted"

    var isInProgress: Bool {
        self == .active || self == .gracePeriod
    }
}

/// Home screen duration chip selection.
enum DurationPreset: Equatable, Hashable, Identifiable, Sendable {
    case minutes(Int)
    case untilMorning
    case custom

    static let standardOptions: [DurationPreset] = [
        .minutes(15),
        .minutes(30),
        .minutes(60),
        .minutes(120),
        .untilMorning,
        .custom,
    ]

    var id: String {
        switch self {
        case .minutes(let value): return "minutes_\(value)"
        case .untilMorning: return "until_morning"
        case .custom: return "custom"
        }
    }

    var chipTitle: String {
        switch self {
        case .minutes(15): return "15分"
        case .minutes(30): return "30分"
        case .minutes(60): return "1時間"
        case .minutes(120): return "2時間"
        case .minutes(let value): return DurationFormatter.japaneseDuration(minutes: value)
        case .untilMorning: return "明日の朝まで"
        case .custom: return "カスタム"
        }
    }
}
