import StoreKit
import StoreKitTest
import SwiftData
import XCTest
@testable import Kumogakure

@MainActor
final class SubscriptionAndHistoryTests: XCTestCase {
    private struct SUT {
        let store: DetoxSessionStore
        let clock: MockClock
        let billingProvider: MockBillingProvider
        let container: ModelContainer
        let repository: SwiftDataSessionRepository
        let preferences: UserPreferencesStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeSUT() throws -> SUT {
        let suiteName = "app.kumogakure.sub.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let preferences = UserPreferencesStore(defaults: defaults)
        let timerEngine = DetoxTimerEngine(clock: clock, scheduler: scheduler)
        let lifecycleMonitor = AppLifecycleMonitor(
            clock: clock,
            scheduler: scheduler,
            backgroundTaskManager: MockBackgroundTaskManager(),
            notificationCenter: NotificationCenter()
        )
        let audioManager = AmbientAudioManager(
            sessionManager: MockAudioSession(),
            playerFactory: { MockAudioPlayer(url: $0) },
            resourceLocator: { sound in
                sound.resourceFileName.map { URL(fileURLWithPath: "/tmp/\($0).m4a") }
            },
            scheduler: scheduler,
            notificationCenter: NotificationCenter()
        )
        let notifications = MockNotificationScheduler()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DetoxSessionRecord.self, configurations: configuration)
        let repository = SwiftDataSessionRepository(modelContext: container.mainContext)
        let billingProvider = MockBillingProvider()
        let subscriptionManager = SubscriptionManager(billing: billingProvider)

        let store = DetoxSessionStore(
            clock: clock,
            timerEngine: timerEngine,
            lifecycleMonitor: lifecycleMonitor,
            audioManager: audioManager,
            notificationScheduler: notifications,
            repository: repository,
            preferences: preferences,
            userIDProvider: KeychainHelper(store: InMemoryKeychainStore()),
            idleTimerController: MockIdleTimerController(),
            apiClient: MockAPIClient(),
            subscriptionManager: subscriptionManager
        )

        return SUT(
            store: store,
            clock: clock,
            billingProvider: billingProvider,
            container: container,
            repository: repository,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func testPurchaseSuccessActivatesProInStore() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        await sut.store.subscriptionManager.start(appUserID: sut.store.anonymousUserUUID)
        XCTAssertFalse(sut.store.isPro)

        let purchased = await sut.store.subscriptionManager.purchase(plan: .yearly)
        XCTAssertTrue(purchased)
        XCTAssertTrue(sut.store.subscriptionManager.isPro)
        XCTAssertTrue(sut.store.isPro)
        XCTAssertEqual(sut.store.subscriptionManager.entitlement.entitlementID, AppConfig.entitlementID)
    }

    func testUserCancellationProducesNoErrorAlert() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.billingProvider.setPurchaseOutcome(.userCancelled)
        let purchased = await sut.store.subscriptionManager.purchase(plan: .monthly)
        XCTAssertFalse(purchased)
        XCTAssertFalse(sut.store.isPro)
        XCTAssertNil(sut.store.subscriptionManager.errorMessage)
    }

    func testRestorePurchasesSuccessAndEmptyMessageBranches() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.billingProvider.setEntitlement(.inactive)
        let emptyResult = await sut.store.subscriptionManager.restorePurchases()
        XCTAssertFalse(emptyResult)
        XCTAssertEqual(
            sut.store.subscriptionManager.restoreMessage,
            "復元可能な購入履歴は見つかりませんでした。"
        )

        sut.billingProvider.setEntitlement(
            EntitlementSnapshot(
                entitlementID: AppConfig.entitlementID,
                isActive: true,
                activeProductID: AppConfig.monthlyProductID,
                expirationDate: sut.clock.now.addingTimeInterval(86_400 * 30)
            )
        )
        let restoredResult = await sut.store.subscriptionManager.restorePurchases()
        XCTAssertTrue(restoredResult)
        XCTAssertTrue(sut.store.isPro)
        XCTAssertEqual(
            sut.store.subscriptionManager.restoreMessage,
            "隠者プランを復元しました。"
        )
    }

    func testProExpirationFallsBackSettingsButPreservesAllHistoryRecords() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let day: TimeInterval = 86_400
        let oldRecord = DetoxSessionRecord(
            plannedDurationSeconds: 3600,
            actualDurationSeconds: 3600,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-12 * day),
            plannedEndsAt: sut.clock.now.addingTimeInterval(-12 * day + 3600),
            finishedAt: sut.clock.now.addingTimeInterval(-12 * day + 3600)
        )
        let recentRecord = DetoxSessionRecord(
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 1800,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-2 * day),
            plannedEndsAt: sut.clock.now.addingTimeInterval(-2 * day + 1800),
            finishedAt: sut.clock.now.addingTimeInterval(-2 * day + 1800)
        )
        try sut.repository.insert(oldRecord)
        try sut.repository.insert(recentRecord)
        try sut.repository.save()
        sut.store.refreshCumulativeSummary()

        // Active Pro sees all history and can select Pro features.
        await sut.store.subscriptionManager.start(appUserID: sut.store.anonymousUserUUID)
        _ = await sut.store.subscriptionManager.purchase(plan: .yearly)
        XCTAssertTrue(sut.store.isPro)

        sut.preferences.selectTheme(.moonlitLake)
        sut.preferences.selectSound(.bonfire)
        sut.preferences.selectPurpose(.custom)
        sut.preferences.selectCardStyle(.sumiNight)
        sut.preferences.hideWatermark = true

        XCTAssertEqual(sut.store.fetchRecentHistoryRecords().count, 2)
        XCTAssertEqual(sut.store.countLockedHistoryRecords(), 0)

        // Subscription expires -> settings fall back, 12-day-old record is preserved in SwiftData.
        await sut.billingProvider.emitUpdate(.inactive)
        await Task.yield()

        XCTAssertFalse(sut.store.isPro)
        XCTAssertEqual(sut.preferences.selectedTheme, .mistyMountain)
        XCTAssertEqual(sut.preferences.selectedSound, .rain)
        XCTAssertEqual(sut.preferences.selectedPurpose, .rest)
        XCTAssertEqual(sut.preferences.selectedCardStyle, .washiClassic)
        XCTAssertFalse(sut.preferences.hideWatermark)

        XCTAssertEqual(sut.store.fetchRecentHistoryRecords().count, 1)
        XCTAssertEqual(sut.store.countLockedHistoryRecords(), 1)
        XCTAssertEqual(sut.store.cumulativeSummary.completedCount, 2)
        XCTAssertEqual(sut.store.cumulativeSummary.totalCompletedSeconds, 5400)
        XCTAssertEqual(try sut.repository.fetchAllRecords().count, 2)

        // Re-subscribing immediately unlocks full history again.
        _ = await sut.store.subscriptionManager.purchase(plan: .monthly)
        XCTAssertEqual(sut.store.fetchRecentHistoryRecords().count, 2)
        XCTAssertEqual(sut.store.countLockedHistoryRecords(), 0)
    }

    func testHistoryAnalyticsSummarizesCompletedSessionsByWeekdayAndTimeBand() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // 2026-11-23 is Monday in JST.
        let mondayMorning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 6, minute: 30))!
        let wednesdayEvening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 20, minute: 0))!
        let canceledSession = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12, minute: 0))!

        let records = [
            DetoxSessionRecord(
                plannedDurationSeconds: 1800,
                actualDurationSeconds: 1800,
                statusRaw: SessionStatus.completed.rawValue,
                startedAt: mondayMorning,
                plannedEndsAt: mondayMorning.addingTimeInterval(1800),
                finishedAt: mondayMorning.addingTimeInterval(1800)
            ),
            DetoxSessionRecord(
                plannedDurationSeconds: 3600,
                actualDurationSeconds: 3600,
                statusRaw: SessionStatus.completed.rawValue,
                startedAt: wednesdayEvening,
                plannedEndsAt: wednesdayEvening.addingTimeInterval(3600),
                finishedAt: wednesdayEvening.addingTimeInterval(3600)
            ),
            DetoxSessionRecord(
                plannedDurationSeconds: 1800,
                actualDurationSeconds: 600,
                statusRaw: SessionStatus.canceled.rawValue,
                startedAt: canceledSession,
                plannedEndsAt: canceledSession.addingTimeInterval(1800),
                finishedAt: canceledSession.addingTimeInterval(600)
            ),
        ]

        let summary = HistoryAnalytics.summarize(records: records, calendar: calendar)
        XCTAssertEqual(summary.totalCompletedCount, 2)
        XCTAssertEqual(summary.totalCompletedMinutes, 90)

        let monday = summary.weekdayStats.first(where: { $0.label == "月" })
        let wednesday = summary.weekdayStats.first(where: { $0.label == "水" })
        XCTAssertEqual(monday?.totalMinutes, 30)
        XCTAssertEqual(monday?.sessionCount, 1)
        XCTAssertEqual(wednesday?.totalMinutes, 60)
        XCTAssertEqual(wednesday?.sessionCount, 1)

        let earlyMorning = summary.timeBandStats.first(where: { $0.band == .earlyMorning })
        let evening = summary.timeBandStats.first(where: { $0.band == .evening })
        let daytime = summary.timeBandStats.first(where: { $0.band == .daytime })
        XCTAssertEqual(earlyMorning?.totalMinutes, 30)
        XCTAssertEqual(evening?.totalMinutes, 60)
        XCTAssertEqual(daytime?.totalMinutes, 0)
    }

    func testLocalStoreKitConfigurationAndPurchaseFlow() async throws {
        let bundle = Bundle(for: SubscriptionAndHistoryTests.self)
        let configURL = try XCTUnwrap(
            bundle.url(forResource: "Kumogakure", withExtension: "storekit"),
            "Kumogakure.storekit must be bundled in KumogakureTests resources"
        )

        let session = try SKTestSession(contentsOf: configURL)
        session.disableDialogs = true
        session.storefront = "JPN"
        session.locale = Locale(identifier: "ja_JP")
        session.resetToDefaultState()
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        let manager = SubscriptionManager(billing: StoreKitBillingClient())
        await manager.start(appUserID: UUID().uuidString.lowercased())

        XCTAssertFalse(manager.isPro)
        XCTAssertEqual(manager.products.count, 2)

        let yearly = manager.product(for: .yearly)
        let monthly = manager.product(for: .monthly)
        XCTAssertEqual(yearly.id, AppConfig.yearlyProductID)
        XCTAssertEqual(yearly.introductoryTrialDays, 7)
        XCTAssertTrue(yearly.isEligibleForIntroOffer)

        XCTAssertEqual(monthly.id, AppConfig.monthlyProductID)
        XCTAssertNil(monthly.introductoryTrialDays)
        XCTAssertFalse(monthly.isEligibleForIntroOffer)

        let purchased = await manager.purchase(plan: .yearly)
        XCTAssertTrue(purchased)
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.entitlement.entitlementID, AppConfig.entitlementID)
        XCTAssertEqual(manager.entitlement.activeProductID, AppConfig.yearlyProductID)

        try session.expireSubscription(productIdentifier: AppConfig.yearlyProductID)
        for _ in 0..<25 {
            await manager.refreshEntitlement()
            if !manager.isPro {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(manager.isPro)
    }
}
