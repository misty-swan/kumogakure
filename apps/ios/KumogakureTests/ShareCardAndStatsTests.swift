import SwiftData
import XCTest
@testable import Kumogakure

@MainActor
final class ShareCardAndStatsTests: XCTestCase {
    private struct SUT {
        let store: DetoxSessionStore
        let clock: MockClock
        let scheduler: ManualTestScheduler
        let apiClient: MockAPIClient
        let container: ModelContainer
        let preferences: UserPreferencesStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeSUT() throws -> SUT {
        let suiteName = "app.kumogakure.share.tests.\(UUID().uuidString)"
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
        let apiClient = MockAPIClient()
        let subscriptionManager = SubscriptionManager(billing: MockBillingProvider())

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
            apiClient: apiClient,
            subscriptionManager: subscriptionManager
        )

        return SUT(
            store: store,
            clock: clock,
            scheduler: scheduler,
            apiClient: apiClient,
            container: container,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func testShareCardRendererProduces1080SquarePNGAcrossAllStyles() throws {
        let endsAt = Date(timeIntervalSince1970: 1_795_160_400)
        let pngMagicBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        for style in CardStyle.allCases {
            let payload = AbsenceCardPayload(
                theme: .mistyMountain,
                cardStyle: style,
                hideWatermark: style != .washiClassic,
                displayName: "霧崎",
                message: "読書してきます",
                mode: .activeAbsence(plannedEndsAt: endsAt, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            )
            let data = try XCTUnwrap(ShareCardRenderer.renderPNGData(payload: payload, format: .square))
            XCTAssertEqual(Array(data.prefix(8)), pngMagicBytes)

            let image = try XCTUnwrap(ShareCardRenderer.renderImage(payload: payload, format: .square))
            XCTAssertEqual(image.scale, 1.0, accuracy: 0.001)
            XCTAssertEqual(image.cgImage?.width, 1080)
            XCTAssertEqual(image.cgImage?.height, 1080)
        }
    }

    func testShareCardRendererProduces1080x1920StoryPNG() throws {
        let endsAt = Date(timeIntervalSince1970: 1_795_160_400)
        let payload = AbsenceCardPayload(
            theme: .rainyBamboo,
            cardStyle: .sumiNight,
            hideWatermark: false,
            displayName: nil,
            message: "少しの間、ひと休みします",
            mode: .activeAbsence(plannedEndsAt: endsAt, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        )
        let image = try XCTUnwrap(ShareCardRenderer.renderImage(payload: payload, format: .story))
        XCTAssertEqual(image.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(image.cgImage?.width, 1080)
        XCTAssertEqual(image.cgImage?.height, 1920)
    }

    func testCompletionCardRendererProduces1080SquarePNG() throws {
        let completedAt = Date(timeIntervalSince1970: 1_795_160_400)
        let payload = AbsenceCardPayload(
            theme: .moonlitLake,
            cardStyle: .indigoMist,
            hideWatermark: true,
            displayName: "旅人",
            message: nil,
            mode: .completedReturn(
                actualDurationSeconds: 5400,
                completedAt: completedAt,
                timeZone: TimeZone(identifier: "Asia/Tokyo")!
            )
        )
        let image = try XCTUnwrap(ShareCardRenderer.renderImage(payload: payload, format: .square))
        XCTAssertEqual(image.cgImage?.width, 1080)
        XCTAssertEqual(image.cgImage?.height, 1080)
    }

    func testShareMessageBuilderMatchesCanonicalTemplates() {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let endsAt = Date(timeIntervalSince1970: 1_795_153_200) // 2026-11-20T14:40:00+09:00? Formatted deterministically via DurationFormatter
        let expectedClock = DurationFormatter.clockTimeString(endsAt, timeZone: jst)

        let urlMsg = ShareMessageBuilder.urlShareText(
            plannedEndsAt: endsAt,
            timeZone: jst,
            message: "読書してきます",
            shareURL: "https://kumogakure.app/s/k9x2m7p4q8"
        )
        XCTAssertEqual(
            urlMsg,
            "ただいま雲隠れ中です（\(expectedClock) 帰還予定）。読書してきます\nhttps://kumogakure.app/s/k9x2m7p4q8\n#雲隠れ"
        )

        let imgMsg = ShareMessageBuilder.imageShareText(
            plannedEndsAt: endsAt,
            timeZone: jst,
            message: nil
        )
        XCTAssertEqual(
            imgMsg,
            "ただいま雲隠れ中です（\(expectedClock) 帰還予定）。\n#雲隠れ #デジタルデトックス"
        )

        let completeMsg = ShareMessageBuilder.completionShareText(actualDurationSeconds: 5400)
        XCTAssertEqual(
            completeMsg,
            "1時間30分の雲隠れから帰還しました。静かな時間でした。\n#雲隠れ"
        )
    }

    func testGraphemeLimiterPreservesEmojiClustersAndStripsForbiddenChars() {
        let twentyFiveFamilies = String(repeating: "👨‍👩‍👧", count: 25)
        let clampedName = TextInputLimiter.clampedGraphemes(
            twentyFiveFamilies,
            limit: AppConfig.maxDisplayNameLength
        )
        XCTAssertEqual(clampedName.count, 20)
        XCTAssertEqual(clampedName, String(repeating: "👨‍👩‍👧", count: 20))

        let fortyFiveJapanese = String(repeating: "あ", count: 45)
        let clampedMessage = TextInputLimiter.clampedGraphemes(
            fortyFiveJapanese,
            limit: AppConfig.maxMessageLength
        )
        XCTAssertEqual(clampedMessage.count, 40)

        let sanitized = TextInputLimiter.sanitizedOptional(
            "  hello\u{202E}world\n\0test  ",
            limit: AppConfig.maxMessageLength
        )
        XCTAssertEqual(sanitized, "helloworld test")
    }

    func testOthersActiveCountSubtractsSelfOnlyWhenRegisteredAndZeroFallback() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        // While idle on Home screen: show raw count without subtracting self.
        sut.apiClient.statsHandler = {
            ActiveStatsResponse(activeCount: 5, sampledAt: 1_795_150_000)
        }
        await sut.store.refreshActiveParticipants()
        XCTAssertEqual(sut.store.othersActiveCount, 5)
        XCTAssertEqual(
            QuietStatusBadge.formattedMessage(
                othersCount: sut.store.othersActiveCount,
                activeCountPrefix: "現在、",
                zeroCopy: "いま、穏やかな静寂が広がっています"
            ),
            "現在、5 人が雲隠れしています"
        )

        // When active with a registered remote session and server reports 1 (only self): 0 -> serene fallback copy.
        sut.apiClient.statsHandler = {
            ActiveStatsResponse(activeCount: 1, sampledAt: 1_795_150_100)
        }
        let remote = CreateSessionResponse(
            id: "self123456",
            ownerToken: "self-tok",
            status: "active",
            startedAt: 1_795_150_000,
            endsAt: 1_795_150_900,
            expiresAt: 1_795_236_400,
            shareURL: "https://kumogakure.app/s/self123456",
            ogpImageURL: "https://kumogakure.app/ogp/self123456.png"
        )
        sut.store.startSession(durationMinutes: 15, isPublic: true, remoteSession: remote)
        await sut.store.awaitPendingBackgroundSync()

        XCTAssertEqual(sut.store.othersActiveCount, 0)
        let detoxZeroMessage = QuietStatusBadge.formattedMessage(
            othersCount: sut.store.othersActiveCount,
            activeCountPrefix: "現在、ほかに ",
            zeroCopy: "いま、深い静寂が広がっています"
        )
        XCTAssertEqual(detoxZeroMessage, "いま、深い静寂が広がっています")
        XCTAssertFalse(detoxZeroMessage.contains("0 人"))

        // When server reports 4 while active: 4 - 1 = 3.
        sut.apiClient.statsHandler = {
            ActiveStatsResponse(activeCount: 4, sampledAt: 1_795_150_200)
        }
        await sut.store.refreshActiveParticipants()
        XCTAssertEqual(sut.store.othersActiveCount, 3)
        XCTAssertEqual(
            QuietStatusBadge.formattedMessage(
                othersCount: sut.store.othersActiveCount,
                activeCountPrefix: "現在、ほかに ",
                zeroCopy: "いま、深い静寂が広がっています"
            ),
            "現在、ほかに 3 人が雲隠れしています"
        )
    }

    func testRefreshActiveParticipantsSilentlyPreservesCachedCountOnFailure() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        sut.apiClient.statsHandler = {
            ActiveStatsResponse(activeCount: 7, sampledAt: 1_795_150_000)
        }
        await sut.store.refreshActiveParticipants()
        XCTAssertEqual(sut.store.othersActiveCount, 7)

        sut.apiClient.statsHandler = {
            throw APIError.networkError(description: "offline")
        }
        await sut.store.refreshActiveParticipants()
        XCTAssertEqual(sut.store.othersActiveCount, 7)
    }

    func testSharePreparationDisablesMonitoringAndQuietStartFinishRaceSyncs() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        // 1. Entering S-02 disables lifecycle penalty even if user leaves app for > 10s (e.g. share extension).
        sut.store.openSharePreparation()
        XCTAssertEqual(sut.store.state, .preparingShare)
        XCTAssertFalse(sut.store.lifecycleMonitor.isMonitoringEnabled)

        sut.store.handleScenePhaseChange(.background)
        sut.scheduler.advance(by: 30)
        sut.store.handleScenePhaseChange(.active)
        XCTAssertEqual(sut.store.state, .preparingShare)

        sut.store.cancelSharePreparation()
        XCTAssertEqual(sut.store.state, .idle)

        // 2. Quiet start race: user cancels locally BEFORE POST /sessions finishes.
        let gate = AsyncGate()
        sut.apiClient.createHandler = { req in
            await gate.wait()
            return CreateSessionResponse(
                id: "raced12345",
                ownerToken: "raced-token",
                status: "active",
                startedAt: 1_795_150_000,
                endsAt: 1_795_150_900,
                expiresAt: 1_795_236_400,
                shareURL: nil,
                ogpImageURL: nil
            )
        }

        sut.store.startSession(durationMinutes: 15, isPublic: false)
        sut.scheduler.advance(by: 30)
        sut.store.confirmEarlyCancel()
        XCTAssertEqual(sut.apiClient.finishCalls.count, 0)

        await gate.open()
        await sut.store.awaitPendingBackgroundSync()

        XCTAssertEqual(sut.apiClient.finishCalls.count, 1)
        XCTAssertEqual(sut.apiClient.finishCalls.first?.id, "raced12345")
        XCTAssertEqual(sut.apiClient.finishCalls.first?.ownerToken, "raced-token")
        XCTAssertEqual(sut.apiClient.finishCalls.first?.outcome, .canceled)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }
}
