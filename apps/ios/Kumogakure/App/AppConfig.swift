import Foundation

/// Central configuration for bundle identifiers, RevenueCat keys, endpoints, and timer bounds.
enum AppConfig {
    static let bundleIdentifier = "app.kumogakure.ios"
    static let keychainService = bundleIdentifier
    static let keychainAnonymousUserUUIDAccount = "kumogakure.anonymous_user_uuid"

    // MARK: - RevenueCat / StoreKit (Canonical IDs)
    static let subscriptionGroupName = "Kumogakure Hermit Pro"
    static let entitlementID = "hermit_pro"
    static let offeringID = "default"
    static let monthlyProductID = "app.kumogakure.pro.monthly"
    static let yearlyProductID = "app.kumogakure.pro.yearly"
    static let revenueCatPublicAPIKey = ""

    // MARK: - Endpoints & External Links
    static var apiBaseURL: URL {
        #if DEBUG
        return URL(string: "https://kumogakure-api-dev-fpdy7efquq-an.a.run.app")!
        #else
        return URL(string: "https://kumogakure.app")!
        #endif
    }

    static let contactFormURL = URL(
        string: "https://docs.google.com/forms/d/e/1FAIpQLScOjICc8nN83rTRGXd2oYbvBicAxNB8yvrFXsNFjE00xLIqgQ/viewform"
    )!

    static let appleStandardEULAURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    static var privacyPolicyURL: URL {
        apiBaseURL.appendingPathComponent("legal/privacy")
    }

    static var termsOfServiceURL: URL {
        apiBaseURL.appendingPathComponent("legal/terms")
    }

    // MARK: - API & Text Bounds
    static let apiRequestTimeoutSeconds: TimeInterval = 5.0
    static let apiResourceTimeoutSeconds: TimeInterval = 10.0
    static let sessionTTLSeconds: TimeInterval = 86_400
    static let activeStatsRefreshIntervalSeconds: TimeInterval = 60.0
    static let maxDisplayNameLength = 20
    static let maxMessageLength = 40

    // MARK: - Timer & Lifecycle Bounds
    static let minDurationMinutes = 15
    static let maxDurationMinutes = 720
    static let durationStepMinutes = 15
    static let defaultDurationMinutes = 30

    static let minMorningTargetMinutes = 300 // 05:00
    static let maxMorningTargetMinutes = 600 // 10:00
    static let defaultMorningTargetMinutes = 420 // 07:00
    static let morningTargetStepMinutes = 30

    static let lockDetectionDelaySeconds: TimeInterval = 1.5
    static let gracePeriodDurationSeconds: TimeInterval = 10.0

    // MARK: - Audio & UX Thresholds
    static let audioFadeOutDurationSeconds: TimeInterval = 1.5
    static let audioPreviewDurationSeconds: TimeInterval = 2.0
    static let freeHistoryRetentionDays = 7
    static let proBannerCompletionThreshold = 3
    static let controlsAutoDimDelaySeconds: TimeInterval = 5.0
}
