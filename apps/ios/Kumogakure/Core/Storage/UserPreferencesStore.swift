import Foundation
import Observation

/// Non-sensitive UI & timer preferences persisted in `UserDefaults` (`database-design.md` §2.4).
@Observable
@MainActor
final class UserPreferencesStore {
    enum Keys {
        static let durationMinutes = "pref_duration_minutes"
        static let purposeID = "pref_purpose_id"
        static let themeID = "pref_theme_id"
        static let soundID = "pref_sound_id"
        static let cardStyle = "pref_card_style"
        static let displayName = "pref_display_name"
        static let hideWatermark = "pref_hide_watermark"
        static let keepScreenOn = "pref_keep_screen_on"
        static let morningTargetMinutes = "pref_morning_target_minutes"
        static let hasDismissedProBanner = "has_dismissed_pro_banner"

        // Auxiliary local flags
        static let selectedDurationIsMorning = "pref_selected_duration_is_morning"
        static let lastBackgroundWasScreenLock = "active_session_bg_was_screen_lock"
        static let activeGraceDeadline = "active_session_grace_deadline"
        static let hasRequestedNotificationPermission = "has_requested_notification_permission"
    }

    private let defaults: UserDefaults
    private var storedDurationMinutes: Int
    private var storedMorningTargetMinutes: Int

    var durationMinutes: Int {
        get { storedDurationMinutes }
        set {
            let clamped = Self.clampDuration(newValue)
            storedDurationMinutes = clamped
            defaults.set(clamped, forKey: Keys.durationMinutes)
        }
    }

    var purposeIDRaw: String {
        didSet { defaults.set(purposeIDRaw, forKey: Keys.purposeID) }
    }

    var themeIDRaw: String {
        didSet { defaults.set(themeIDRaw, forKey: Keys.themeID) }
    }

    var soundIDRaw: String {
        didSet { defaults.set(soundIDRaw, forKey: Keys.soundID) }
    }

    var cardStyleRaw: String {
        didSet { defaults.set(cardStyleRaw, forKey: Keys.cardStyle) }
    }

    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.displayName) }
    }

    var hideWatermark: Bool {
        didSet { defaults.set(hideWatermark, forKey: Keys.hideWatermark) }
    }

    var keepScreenOn: Bool {
        didSet { defaults.set(keepScreenOn, forKey: Keys.keepScreenOn) }
    }

    var morningTargetMinutes: Int {
        get { storedMorningTargetMinutes }
        set {
            let clamped = MorningTargetCalculator.clampedTargetMinutes(newValue)
            storedMorningTargetMinutes = clamped
            defaults.set(clamped, forKey: Keys.morningTargetMinutes)
        }
    }

    var hasDismissedProBanner: Bool {
        didSet { defaults.set(hasDismissedProBanner, forKey: Keys.hasDismissedProBanner) }
    }

    var selectedDurationIsMorning: Bool {
        didSet { defaults.set(selectedDurationIsMorning, forKey: Keys.selectedDurationIsMorning) }
    }

    var lastBackgroundWasScreenLock: Bool {
        didSet { defaults.set(lastBackgroundWasScreenLock, forKey: Keys.lastBackgroundWasScreenLock) }
    }

    var activeGraceDeadline: Date? {
        didSet {
            if let activeGraceDeadline {
                defaults.set(activeGraceDeadline.timeIntervalSince1970, forKey: Keys.activeGraceDeadline)
            } else {
                defaults.removeObject(forKey: Keys.activeGraceDeadline)
            }
        }
    }

    var hasRequestedNotificationPermission: Bool {
        didSet { defaults.set(hasRequestedNotificationPermission, forKey: Keys.hasRequestedNotificationPermission) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedDuration = defaults.object(forKey: Keys.durationMinutes) as? Int
            ?? AppConfig.defaultDurationMinutes
        self.storedDurationMinutes = Self.clampDuration(storedDuration)

        self.purposeIDRaw = defaults.string(forKey: Keys.purposeID) ?? PurposeID.rest.rawValue
        self.themeIDRaw = defaults.string(forKey: Keys.themeID) ?? ThemeID.mistyMountain.rawValue
        self.soundIDRaw = defaults.string(forKey: Keys.soundID) ?? SoundID.rain.rawValue
        self.cardStyleRaw = defaults.string(forKey: Keys.cardStyle) ?? CardStyle.washiClassic.rawValue
        self.displayName = defaults.string(forKey: Keys.displayName) ?? ""
        self.hideWatermark = defaults.object(forKey: Keys.hideWatermark) as? Bool ?? false
        self.keepScreenOn = defaults.object(forKey: Keys.keepScreenOn) as? Bool ?? false

        let storedMorning = defaults.object(forKey: Keys.morningTargetMinutes) as? Int
            ?? AppConfig.defaultMorningTargetMinutes
        self.storedMorningTargetMinutes = MorningTargetCalculator.clampedTargetMinutes(storedMorning)

        self.hasDismissedProBanner = defaults.object(forKey: Keys.hasDismissedProBanner) as? Bool ?? false
        self.selectedDurationIsMorning = defaults.object(forKey: Keys.selectedDurationIsMorning) as? Bool ?? false
        self.lastBackgroundWasScreenLock = defaults.object(forKey: Keys.lastBackgroundWasScreenLock) as? Bool ?? false

        if let timestamp = defaults.object(forKey: Keys.activeGraceDeadline) as? Double {
            self.activeGraceDeadline = Date(timeIntervalSince1970: timestamp)
        } else {
            self.activeGraceDeadline = nil
        }

        self.hasRequestedNotificationPermission = defaults.object(
            forKey: Keys.hasRequestedNotificationPermission
        ) as? Bool ?? false
    }

    var selectedPurpose: PurposeID {
        PurposeID(rawValue: purposeIDRaw) ?? .rest
    }

    var selectedTheme: ThemeID {
        ThemeID(rawValue: themeIDRaw) ?? .mistyMountain
    }

    var selectedSound: SoundID {
        SoundID(rawValue: soundIDRaw) ?? .rain
    }

    var selectedCardStyle: CardStyle {
        CardStyle(rawValue: cardStyleRaw) ?? .washiClassic
    }

    var activeDurationPreset: DurationPreset {
        if selectedDurationIsMorning {
            return .untilMorning
        }
        switch durationMinutes {
        case 15, 30, 60, 120:
            return .minutes(durationMinutes)
        default:
            return .custom
        }
    }

    func selectPresetDuration(minutes: Int) {
        selectedDurationIsMorning = false
        durationMinutes = minutes
    }

    func selectUntilMorning() {
        selectedDurationIsMorning = true
    }

    func selectPurpose(_ purpose: PurposeID) {
        purposeIDRaw = purpose.rawValue
    }

    func selectTheme(_ theme: ThemeID) {
        themeIDRaw = theme.rawValue
    }

    func selectSound(_ sound: SoundID) {
        soundIDRaw = sound.rawValue
    }

    func selectCardStyle(_ style: CardStyle) {
        cardStyleRaw = style.rawValue
    }

    /// Falls back Pro-only selections to free defaults when entitlement is inactive (`monetization.md` §5).
    func applyEntitlementFallback(isPro: Bool) {
        let resolvedTheme = ThemeID.resolved(rawValue: themeIDRaw, isPro: isPro)
        if resolvedTheme.rawValue != themeIDRaw {
            themeIDRaw = resolvedTheme.rawValue
        }
        let resolvedSound = SoundID.resolved(rawValue: soundIDRaw, isPro: isPro)
        if resolvedSound.rawValue != soundIDRaw {
            soundIDRaw = resolvedSound.rawValue
        }
        let resolvedPurpose = PurposeID.resolved(rawValue: purposeIDRaw, isPro: isPro)
        if resolvedPurpose.rawValue != purposeIDRaw {
            purposeIDRaw = resolvedPurpose.rawValue
        }
        let resolvedStyle = CardStyle.resolved(rawValue: cardStyleRaw, isPro: isPro)
        if resolvedStyle.rawValue != cardStyleRaw {
            cardStyleRaw = resolvedStyle.rawValue
        }
        if !isPro && hideWatermark {
            hideWatermark = false
        }
    }

    private static func clampDuration(_ value: Int) -> Int {
        min(AppConfig.maxDurationMinutes, max(AppConfig.minDurationMinutes, value))
    }
}
