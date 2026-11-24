import SwiftData
import XCTest
@testable import Kumogakure

@MainActor
final class OfflineFinishQueueTests: XCTestCase {
    private struct SUT {
        let host: String
        let clock: MockClock
        let container: ModelContainer
        let repository: SwiftDataSessionRepository
        let apiClient: KumogakureAPIClient
        let queue: OfflineFinishQueue

        func cleanup() {
            URLProtocolStubStorage.shared.unregister(host: host)
        }
    }

    private func makeSUT() throws -> SUT {
        let host = "offline-\(UUID().uuidString.lowercased()).kumogakure.local"
        let clock = MockClock()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DetoxSessionRecord.self, configurations: configuration)
        let repository = SwiftDataSessionRepository(modelContext: container.mainContext)
        let apiClient = KumogakureAPIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: StubURLProtocol.makeStubbedSession()
        )
        let queue = OfflineFinishQueue(
            apiClient: apiClient,
            repository: repository,
            clock: clock
        )
        return SUT(
            host: host,
            clock: clock,
            container: container,
            repository: repository,
            apiClient: apiClient,
            queue: queue
        )
    }

    func testTemporary500KeepsSyncFlagAndOwnerTokenThenClearsOnRetry() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let record = DetoxSessionRecord(
            remoteID: "rem1234567",
            ownerToken: "owner-secret-token",
            isPublic: true,
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 1800,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-1800),
            plannedEndsAt: sut.clock.now,
            finishedAt: sut.clock.now,
            needsRemoteFinishSync: true
        )
        try sut.repository.insert(record)
        try sut.repository.save()

        URLProtocolStubStorage.shared.register(host: sut.host) { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await sut.queue.submitFinish(for: record)
        XCTAssertTrue(record.needsRemoteFinishSync)
        XCTAssertEqual(record.ownerToken, "owner-secret-token")

        // Simulate recovery on next launch / foreground return.
        URLProtocolStubStorage.shared.register(host: sut.host) { request, body in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-secret-token")
            let decoded = try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
            XCTAssertEqual(decoded?["outcome"] as? String, "completed")
            let payload = """
            {"id":"rem1234567","status":"completed","finished_at":1795151800}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        await sut.queue.flushPendingFinishes()
        XCTAssertFalse(record.needsRemoteFinishSync)
        XCTAssertNil(record.ownerToken)
        XCTAssertEqual(try sut.repository.fetchPendingRemoteFinishRecords().count, 0)
    }

    func testNetworkOfflineErrorRetriesAndClearsOwnerTokenOnRecovery() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let record = DetoxSessionRecord(
            remoteID: "offline123",
            ownerToken: "offline-token",
            isPublic: false,
            plannedDurationSeconds: 900,
            actualDurationSeconds: 900,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-900),
            plannedEndsAt: sut.clock.now,
            finishedAt: sut.clock.now,
            needsRemoteFinishSync: true
        )
        try sut.repository.insert(record)
        try sut.repository.save()

        URLProtocolStubStorage.shared.register(host: sut.host) { _, _ in
            throw URLError(.notConnectedToInternet)
        }

        await sut.queue.submitFinish(for: record)
        XCTAssertTrue(record.needsRemoteFinishSync)
        XCTAssertEqual(record.ownerToken, "offline-token")

        URLProtocolStubStorage.shared.register(host: sut.host) { request, _ in
            let payload = """
            {"id":"offline123","status":"completed","finished_at":1795150900}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        await sut.queue.flushPendingFinishes()
        XCTAssertFalse(record.needsRemoteFinishSync)
        XCTAssertNil(record.ownerToken)
    }

    func testInterruptedSessionMapsToCanceledOutcome() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let record = DetoxSessionRecord(
            remoteID: "int1234567",
            ownerToken: "int-token",
            isPublic: true,
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 240,
            statusRaw: SessionStatus.interrupted.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-240),
            plannedEndsAt: sut.clock.now.addingTimeInterval(1560),
            finishedAt: sut.clock.now,
            needsRemoteFinishSync: true
        )
        try sut.repository.insert(record)
        try sut.repository.save()

        URLProtocolStubStorage.shared.register(host: sut.host) { request, body in
            let decoded = try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
            XCTAssertEqual(decoded?["outcome"] as? String, "canceled")
            let payload = """
            {"id":"int1234567","status":"canceled","finished_at":1795150240}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        await sut.queue.submitFinish(for: record)
        XCTAssertFalse(record.needsRemoteFinishSync)
        XCTAssertNil(record.ownerToken)
    }

    func testExpiredSessionBeyond24HoursDiscardsWithoutNetworkCall() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let startedOver24HoursAgo = sut.clock.now.addingTimeInterval(-(AppConfig.sessionTTLSeconds + 120))
        let record = DetoxSessionRecord(
            remoteID: "exp1234567",
            ownerToken: "exp-token",
            isPublic: true,
            plannedDurationSeconds: 1800,
            actualDurationSeconds: 1800,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: startedOver24HoursAgo,
            plannedEndsAt: startedOver24HoursAgo.addingTimeInterval(1800),
            finishedAt: startedOver24HoursAgo.addingTimeInterval(1800),
            needsRemoteFinishSync: true
        )
        try sut.repository.insert(record)
        try sut.repository.save()

        URLProtocolStubStorage.shared.register(host: sut.host) { request, _ in
            XCTFail("Expired session should not perform network request")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await sut.queue.flushPendingFinishes()
        XCTAssertTrue(URLProtocolStubStorage.shared.recordedRequests(forHost: sut.host).isEmpty)
        XCTAssertFalse(record.needsRemoteFinishSync)
        XCTAssertNil(record.ownerToken)
    }

    func testPermanent401Or410ClearsSyncFlagWithoutRetrying() async throws {
        let sut = try makeSUT()
        defer { sut.cleanup() }

        let record401 = DetoxSessionRecord(
            remoteID: "unauth1234",
            ownerToken: "bad-token",
            isPublic: true,
            plannedDurationSeconds: 900,
            actualDurationSeconds: 900,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-900),
            plannedEndsAt: sut.clock.now,
            finishedAt: sut.clock.now,
            needsRemoteFinishSync: true
        )
        let record410 = DetoxSessionRecord(
            remoteID: "gone123456",
            ownerToken: "gone-token",
            isPublic: true,
            plannedDurationSeconds: 900,
            actualDurationSeconds: 900,
            statusRaw: SessionStatus.canceled.rawValue,
            startedAt: sut.clock.now.addingTimeInterval(-900),
            plannedEndsAt: sut.clock.now,
            finishedAt: sut.clock.now,
            needsRemoteFinishSync: true
        )
        try sut.repository.insert(record401)
        try sut.repository.insert(record410)
        try sut.repository.save()

        URLProtocolStubStorage.shared.register(host: sut.host) { request, _ in
            if request.url?.path.contains("gone123456") == true {
                let payload = """
                {"error":{"code":"SESSION_EXPIRED","message":"この不在証明は有効期限切れです。"}}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!
                return (response, payload)
            }
            let payload = """
            {"error":{"code":"UNAUTHORIZED","message":"owner_token が不正です。"}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        await sut.queue.flushPendingFinishes()
        XCTAssertFalse(record401.needsRemoteFinishSync)
        XCTAssertNil(record401.ownerToken)
        XCTAssertFalse(record410.needsRemoteFinishSync)
        XCTAssertNil(record410.ownerToken)
        XCTAssertEqual(try sut.repository.fetchPendingRemoteFinishRecords().count, 0)
    }
}
