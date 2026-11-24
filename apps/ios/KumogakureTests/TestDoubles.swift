import Foundation
import UserNotifications
@testable import Kumogakure

final class MockClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date = Date(timeIntervalSince1970: 1_795_150_000)) {
        self.current = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func setNow(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@MainActor
final class ManualTestScheduler: TimerScheduling {
    private final class ScheduledItem: CancellableTask {
        let id: UUID
        var fireAt: Date
        let interval: TimeInterval?
        let action: @MainActor () -> Void
        var isCancelled = false

        init(
            id: UUID = UUID(),
            fireAt: Date,
            interval: TimeInterval?,
            action: @escaping @MainActor () -> Void
        ) {
            self.id = id
            self.fireAt = fireAt
            self.interval = interval
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private let clock: MockClock
    private var items: [ScheduledItem] = []

    init(clock: MockClock) {
        self.clock = clock
    }

    func scheduleOnce(
        after seconds: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let item = ScheduledItem(
            fireAt: clock.now.addingTimeInterval(max(0, seconds)),
            interval: nil,
            action: action
        )
        items.append(item)
        return item
    }

    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableTask {
        let safeInterval = max(0.05, interval)
        let item = ScheduledItem(
            fireAt: clock.now.addingTimeInterval(safeInterval),
            interval: safeInterval,
            action: action
        )
        items.append(item)
        return item
    }

    /// Advances `clock` by `seconds`, firing due one-shot and repeating timers in chronological order.
    func advance(by seconds: TimeInterval) {
        let target = clock.now.addingTimeInterval(max(0, seconds))
        while true {
            items.removeAll { $0.isCancelled }
            guard let next = items
                .filter({ $0.fireAt <= target })
                .min(by: { $0.fireAt < $1.fireAt })
            else {
                break
            }

            if next.fireAt > clock.now {
                clock.setNow(next.fireAt)
            }

            if let interval = next.interval {
                next.fireAt = next.fireAt.addingTimeInterval(interval)
            } else {
                items.removeAll { $0.id == next.id }
            }

            if !next.isCancelled {
                next.action()
            }
        }

        if target > clock.now {
            clock.setNow(target)
        }
    }
}

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func readString(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    func writeString(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[account] = value
        return true
    }

    func deleteValue(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
        return true
    }
}

@MainActor
final class MockAudioSession: AudioSessionManaging {
    struct SetActiveCall: Equatable {
        let active: Bool
        let notifyOthers: Bool
    }

    private(set) var configureCount = 0
    private(set) var setActiveCalls: [SetActiveCall] = []
    var shouldThrowOnActivate = false

    func configurePlaybackCategory() throws {
        configureCount += 1
    }

    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        if shouldThrowOnActivate && active {
            throw NSError(domain: "MockAudioSession", code: -1)
        }
        setActiveCalls.append(SetActiveCall(active: active, notifyOthers: notifyOthersOnDeactivation))
    }
}

@MainActor
final class MockAudioPlayer: AudioPlayerControlling {
    let url: URL
    var volume: Float = 1.0
    var numberOfLoops: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var fadeOutCalls: [(volume: Float, duration: TimeInterval)] = []

    init(url: URL) {
        self.url = url
    }

    func prepareToPlay() -> Bool {
        prepareCount += 1
        return true
    }

    func play() -> Bool {
        playCount += 1
        isPlaying = true
        return true
    }

    func pause() {
        pauseCount += 1
        isPlaying = false
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }

    func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
        self.volume = volume
        fadeOutCalls.append((volume: volume, duration: duration))
    }
}

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    private(set) var requestAuthorizationCount = 0
    var authorizationGrantResult = true
    private(set) var scheduledCompletions: [(sessionID: UUID, endsAt: Date)] = []
    private(set) var canceledCompletions: [UUID] = []
    private(set) var graceWarningScheduledCount = 0
    private(set) var graceWarningCanceledCount = 0

    func requestAuthorizationIfNeeded() async -> Bool {
        requestAuthorizationCount += 1
        return authorizationGrantResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationGrantResult ? .authorized : .denied
    }

    func scheduleCompletionNotification(sessionID: UUID, endsAt: Date) {
        scheduledCompletions.append((sessionID: sessionID, endsAt: endsAt))
    }

    func cancelCompletionNotification(sessionID: UUID) {
        canceledCompletions.append(sessionID)
    }

    func scheduleGraceWarningNotification() {
        graceWarningScheduledCount += 1
    }

    func cancelGraceWarningNotification() {
        graceWarningCanceledCount += 1
    }
}

@MainActor
final class MockIdleTimerController: IdleTimerControlling {
    var isIdleTimerDisabled: Bool = false {
        didSet {
            history.append(isIdleTimerDisabled)
        }
    }
    private(set) var history: [Bool] = []
}

@MainActor
final class MockBackgroundTaskManager: BackgroundTaskManaging {
    private var nextID = 100
    private(set) var beganTaskNames: [String] = []
    private(set) var endedTaskIDs: [Int] = []

    func beginBackgroundTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> Int {
        beganTaskNames.append(name)
        nextID += 1
        return nextID
    }

    func endBackgroundTask(_ identifier: Int) {
        endedTaskIDs.append(identifier)
    }
}

// MARK: - Week 4 Network & Billing Test Doubles

final class URLProtocolStubStorage: @unchecked Sendable {
    static let shared = URLProtocolStubStorage()

    typealias Handler = @Sendable (URLRequest, Data?) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handlersByHost: [String: Handler] = [:]
    private var recordedRequestsByHost: [String: [(request: URLRequest, body: Data?)]] = [:]

    func register(host: String, handler: @escaping Handler) {
        lock.lock()
        handlersByHost[host] = handler
        recordedRequestsByHost[host] = []
        lock.unlock()
    }

    func unregister(host: String) {
        lock.lock()
        handlersByHost.removeValue(forKey: host)
        recordedRequestsByHost.removeValue(forKey: host)
        lock.unlock()
    }

    func recordedRequests(forHost host: String) -> [(request: URLRequest, body: Data?)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequestsByHost[host] ?? []
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let host = request.url?.host else {
            throw URLError(.badURL)
        }
        let body = Self.readBody(from: request)
        lock.lock()
        recordedRequestsByHost[host, default: []].append((request: request, body: body))
        let handler = handlersByHost[host]
        lock.unlock()

        guard let handler else {
            throw URLError(.cannotFindHost)
        }
        return try handler(request, body)
    }

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount <= 0 {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }
}

final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try URLProtocolStubStorage.shared.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeStubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0
        return URLSession(configuration: config)
    }
}

final class MockAPIClient: KumogakureAPIClienting, @unchecked Sendable {
    struct FinishCall: Equatable, Sendable {
        let id: String
        let ownerToken: String
        let outcome: RemoteFinishOutcome
    }

    private let lock = NSLock()
    private var _createRequests: [CreateSessionRequest] = []
    private var _finishCalls: [FinishCall] = []
    private var _fetchStatsCount = 0

    var createHandler: (@Sendable (CreateSessionRequest) async throws -> CreateSessionResponse)?
    var finishHandler: (@Sendable (String, String, RemoteFinishOutcome) async throws -> FinishSessionResponse)?
    var statsHandler: (@Sendable () async throws -> ActiveStatsResponse)?

    var createRequests: [CreateSessionRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _createRequests
    }

    var finishCalls: [FinishCall] {
        lock.lock()
        defer { lock.unlock() }
        return _finishCalls
    }

    var fetchStatsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fetchStatsCount
    }

    func createSession(_ request: CreateSessionRequest) async throws -> CreateSessionResponse {
        lock.lock()
        _createRequests.append(request)
        let handler = createHandler
        lock.unlock()

        if let handler {
            return try await handler(request)
        }
        return CreateSessionResponse(
            id: "mockid1234",
            ownerToken: "mock-owner-token",
            status: "active",
            startedAt: 1_795_150_000,
            endsAt: 1_795_150_000 + Int64(request.durationMinutes * 60),
            expiresAt: 1_795_150_000 + 86_400,
            shareURL: request.isPublic ? "https://kumogakure.app/s/mockid1234" : nil,
            ogpImageURL: request.isPublic ? "https://kumogakure.app/ogp/mockid1234.png" : nil
        )
    }

    func finishSession(
        id: String,
        ownerToken: String,
        outcome: RemoteFinishOutcome
    ) async throws -> FinishSessionResponse {
        lock.lock()
        _finishCalls.append(FinishCall(id: id, ownerToken: ownerToken, outcome: outcome))
        let handler = finishHandler
        lock.unlock()

        if let handler {
            return try await handler(id, ownerToken, outcome)
        }
        return FinishSessionResponse(
            id: id,
            status: outcome.rawValue,
            finishedAt: 1_795_151_800
        )
    }

    func fetchActiveStats() async throws -> ActiveStatsResponse {
        lock.lock()
        _fetchStatsCount += 1
        let handler = statsHandler
        lock.unlock()

        if let handler {
            return try await handler()
        }
        return ActiveStatsResponse(activeCount: 0, sampledAt: 1_795_150_000)
    }
}

final class MockBillingProvider: BillingProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _products: [SubscriptionPlanProduct] = SubscriptionPlanProduct.fallbackCatalog
    private var _entitlement: EntitlementSnapshot = .inactive
    private var _purchaseOutcome: PurchaseOutcome?
    private var _purchaseError: Error?
    private var _restoreError: Error?
    private var _purchaseCallCount = 0
    private var _restoreCallCount = 0
    private var _updateCallback: (@Sendable (EntitlementSnapshot) async -> Void)?

    func setProducts(_ products: [SubscriptionPlanProduct]) {
        lock.lock()
        _products = products
        lock.unlock()
    }

    func setEntitlement(_ entitlement: EntitlementSnapshot) {
        lock.lock()
        _entitlement = entitlement
        lock.unlock()
    }

    func setPurchaseOutcome(_ outcome: PurchaseOutcome?) {
        lock.lock()
        _purchaseOutcome = outcome
        lock.unlock()
    }

    func setPurchaseError(_ error: Error?) {
        lock.lock()
        _purchaseError = error
        lock.unlock()
    }

    func setRestoreError(_ error: Error?) {
        lock.lock()
        _restoreError = error
        lock.unlock()
    }

    var purchaseCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _purchaseCallCount
    }

    var restoreCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _restoreCallCount
    }

    func loadProducts() async throws -> [SubscriptionPlanProduct] {
        lock.lock()
        defer { lock.unlock() }
        return _products
    }

    func currentEntitlement() async -> EntitlementSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _entitlement
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        lock.lock()
        _purchaseCallCount += 1
        let error = _purchaseError
        let outcome = _purchaseOutcome
        lock.unlock()

        if let error {
            throw error
        }
        if let outcome {
            if case .purchased(let snapshot) = outcome {
                setEntitlement(snapshot)
            }
            return outcome
        }

        let active = EntitlementSnapshot(
            entitlementID: AppConfig.entitlementID,
            isActive: true,
            activeProductID: productID,
            expirationDate: Date().addingTimeInterval(86_400 * 30)
        )
        setEntitlement(active)
        return .purchased(active)
    }

    func restorePurchases() async throws -> EntitlementSnapshot {
        lock.lock()
        _restoreCallCount += 1
        let error = _restoreError
        let snapshot = _entitlement
        lock.unlock()

        if let error {
            throw error
        }
        return snapshot
    }

    func startObservingUpdates(
        onUpdate: @escaping @Sendable (EntitlementSnapshot) async -> Void
    ) -> Task<Void, Never> {
        lock.lock()
        _updateCallback = onUpdate
        lock.unlock()
        return Task {}
    }

    func emitUpdate(_ snapshot: EntitlementSnapshot) async {
        setEntitlement(snapshot)
        lock.lock()
        let callback = _updateCallback
        lock.unlock()
        await callback?(snapshot)
    }
}
