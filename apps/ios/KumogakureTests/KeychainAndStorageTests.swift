import SwiftData
import XCTest
@testable import Kumogakure

@MainActor
final class KeychainAndStorageTests: XCTestCase {
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "app.kumogakure.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    func testKeychainGeneratesAndPersistsLowercaseUUIDv4() {
        let store = InMemoryKeychainStore()
        let helper1 = KeychainHelper(store: store)
        let first = helper1.getOrCreateAnonymousUserUUID()

        XCTAssertEqual(first, first.lowercased())
        XCTAssertNotNil(UUID(uuidString: first))

        let helper2 = KeychainHelper(store: store)
        let second = helper2.getOrCreateAnonymousUserUUID()
        XCTAssertEqual(first, second)
    }

    func testUserPreferencesDefaultsAndClamping() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = UserPreferencesStore(defaults: defaults)

        XCTAssertEqual(prefs.durationMinutes, 30)
        XCTAssertEqual(prefs.purposeIDRaw, "rest")
        XCTAssertEqual(prefs.themeIDRaw, "misty_mountain")
        XCTAssertEqual(prefs.soundIDRaw, "rain")
        XCTAssertEqual(prefs.cardStyleRaw, "washi_classic")
        XCTAssertEqual(prefs.displayName, "")
        XCTAssertFalse(prefs.keepScreenOn)
        XCTAssertEqual(prefs.morningTargetMinutes, 420)
        XCTAssertFalse(prefs.hasDismissedProBanner)

        prefs.durationMinutes = 5
        XCTAssertEqual(prefs.durationMinutes, 15)
        prefs.durationMinutes = 900
        XCTAssertEqual(prefs.durationMinutes, 720)

        prefs.morningTargetMinutes = 200
        XCTAssertEqual(prefs.morningTargetMinutes, 300)
        prefs.morningTargetMinutes = 700
        XCTAssertEqual(prefs.morningTargetMinutes, 600)

        let reloaded = UserPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.durationMinutes, 720)
        XCTAssertEqual(reloaded.morningTargetMinutes, 600)
    }

    func testEntitlementFallbackResetsProSelectionsToFreeDefaults() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = UserPreferencesStore(defaults: defaults)
        prefs.selectTheme(.moonlitLake)
        prefs.selectSound(.bonfire)
        prefs.selectPurpose(.custom)
        prefs.selectCardStyle(.sumiNight)

        prefs.applyEntitlementFallback(isPro: false)

        XCTAssertEqual(prefs.selectedTheme, .mistyMountain)
        XCTAssertEqual(prefs.selectedSound, .rain)
        XCTAssertEqual(prefs.selectedPurpose, .rest)
        XCTAssertEqual(prefs.selectedCardStyle, .washiClassic)
    }

    func testSwiftData7DayFilterAndCumulativeSummary() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DetoxSessionRecord.self, configurations: configuration)
        let repository = SwiftDataSessionRepository(modelContext: container.mainContext)

        let now = Date(timeIntervalSince1970: 1_795_500_000)
        let day: TimeInterval = 86_400

        let oldCompleted = DetoxSessionRecord(
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 1800,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: now.addingTimeInterval(-10 * day),
            plannedEndsAt: now.addingTimeInterval(-10 * day + 1800),
            finishedAt: now.addingTimeInterval(-10 * day + 1800)
        )
        let oldCanceled = DetoxSessionRecord(
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 600,
            statusRaw: SessionStatus.canceled.rawValue,
            startedAt: now.addingTimeInterval(-8 * day),
            plannedEndsAt: now.addingTimeInterval(-8 * day + 1800),
            finishedAt: now.addingTimeInterval(-8 * day + 600)
        )
        let recentCompleted = DetoxSessionRecord(
            plannedDurationSeconds: 3600,
            actualDurationSeconds: 3600,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: now.addingTimeInterval(-2 * day),
            plannedEndsAt: now.addingTimeInterval(-2 * day + 3600),
            finishedAt: now.addingTimeInterval(-2 * day + 3600)
        )
        let todayCompleted = DetoxSessionRecord(
            plannedDurationSeconds: 900,
            actualDurationSeconds: 900,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: now.addingTimeInterval(-3600),
            plannedEndsAt: now.addingTimeInterval(-2700),
            finishedAt: now.addingTimeInterval(-2700)
        )

        for record in [oldCompleted, oldCanceled, recentCompleted, todayCompleted] {
            try repository.insert(record)
        }
        try repository.save()

        let summary = try repository.fetchSummary()
        XCTAssertEqual(summary.completedCount, 3)
        XCTAssertEqual(summary.totalCompletedSeconds, 6300)

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let recent = try repository.fetchRecentRecords(since: cutoff)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.map(\.localID), [todayCompleted.localID, recentCompleted.localID])

        let lockedCount = try repository.countOlderRecords(before: cutoff)
        XCTAssertEqual(lockedCount, 2)
    }
}
