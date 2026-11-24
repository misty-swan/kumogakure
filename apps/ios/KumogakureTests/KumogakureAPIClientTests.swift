import XCTest
@testable import Kumogakure

final class KumogakureAPIClientTests: XCTestCase {
    private var host: String!
    private var client: KumogakureAPIClient!

    override func setUp() {
        super.setUp()
        host = "api-\(UUID().uuidString.lowercased()).kumogakure.local"
        let baseURL = URL(string: "https://\(host!)")!
        client = KumogakureAPIClient(
            baseURL: baseURL,
            session: StubURLProtocol.makeStubbedSession()
        )
    }

    override func tearDown() {
        URLProtocolStubStorage.shared.unregister(host: host)
        client = nil
        host = nil
        super.tearDown()
    }

    func testCreatePublicSessionSerializesSnakeCaseJSONAndDecodesResponse() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { request, _ in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/sessions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let payload = """
            {
              "id": "k9x2m7p4q8",
              "owner_token": "8f4e2a1c9b7d034f",
              "status": "active",
              "started_at": 1795153200,
              "ends_at": 1795160400,
              "expires_at": 1795239600,
              "share_url": "https://kumogakure.app/s/k9x2m7p4q8",
              "ogp_image_url": "https://kumogakure.app/ogp/k9x2m7p4q8.png"
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, payload)
        }

        let requestBody = CreateSessionRequest(
            userUUID: "550e8400-e29b-41d4-a716-446655440000",
            durationMinutes: 120,
            themeID: "misty_mountain",
            cardStyle: "washi_classic",
            hideWatermark: false,
            isPublic: true,
            isCustomMessage: false,
            displayName: "霧崎",
            message: "読書してきます",
            timezone: "Asia/Tokyo"
        )

        let response = try await client.createSession(requestBody)
        XCTAssertEqual(response.id, "k9x2m7p4q8")
        XCTAssertEqual(response.ownerToken, "8f4e2a1c9b7d034f")
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.endsAt, 1_795_160_400)
        XCTAssertEqual(response.shareURL, "https://kumogakure.app/s/k9x2m7p4q8")
        XCTAssertEqual(response.ogpImageURL, "https://kumogakure.app/ogp/k9x2m7p4q8.png")

        let recorded = try XCTUnwrap(URLProtocolStubStorage.shared.recordedRequests(forHost: host).first)
        let bodyData = try XCTUnwrap(recorded.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(json["user_uuid"] as? String, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(json["duration_minutes"] as? Int, 120)
        XCTAssertEqual(json["theme_id"] as? String, "misty_mountain")
        XCTAssertEqual(json["card_style"] as? String, "washi_classic")
        XCTAssertEqual(json["hide_watermark"] as? Bool, false)
        XCTAssertEqual(json["is_public"] as? Bool, true)
        XCTAssertEqual(json["is_custom_message"] as? Bool, false)
        XCTAssertEqual(json["display_name"] as? String, "霧崎")
        XCTAssertEqual(json["message"] as? String, "読書してきます")
        XCTAssertEqual(json["timezone"] as? String, "Asia/Tokyo")
    }

    func testCreatePrivateSessionDecodesNullShareURLs() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { request, _ in
            let payload = """
            {
              "id": "priv123456",
              "owner_token": "tok999",
              "status": "active",
              "started_at": 1795153200,
              "ends_at": 1795155000,
              "expires_at": 1795239600,
              "share_url": null,
              "ogp_image_url": null
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        let response = try await client.createSession(
            CreateSessionRequest(
                userUUID: "550e8400-e29b-41d4-a716-446655440000",
                durationMinutes: 30,
                themeID: "misty_mountain",
                cardStyle: "washi_classic",
                hideWatermark: false,
                isPublic: false,
                isCustomMessage: false,
                displayName: nil,
                message: nil,
                timezone: "Asia/Tokyo"
            )
        )
        XCTAssertEqual(response.id, "priv123456")
        XCTAssertNil(response.shareURL)
        XCTAssertNil(response.ogpImageURL)
    }

    func testFinishSessionSendsBearerOwnerTokenHeader() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { request, body in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/sessions/k9x2m7p4q8/finish")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-owner-token")

            let decoded = try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
            XCTAssertEqual(decoded?["outcome"] as? String, "completed")

            let payload = """
            {
              "id": "k9x2m7p4q8",
              "status": "completed",
              "finished_at": 1795160402
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        let response = try await client.finishSession(
            id: "k9x2m7p4q8",
            ownerToken: "secret-owner-token",
            outcome: .completed
        )
        XCTAssertEqual(response.id, "k9x2m7p4q8")
        XCTAssertEqual(response.status, "completed")
        XCTAssertEqual(response.finishedAt, 1_795_160_402)
    }

    func testFetchActiveStatsDecodesActiveCount() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/stats/active")
            let payload = """
            {
              "active_count": 42,
              "sampled_at": 1795154000
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        let stats = try await client.fetchActiveStats()
        XCTAssertEqual(stats.activeCount, 42)
        XCTAssertEqual(stats.sampledAt, 1_795_154_000)
    }

    func testServerErrorEnvelopeParsesProRequiredAndPolicyViolation() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { request, _ in
            let payload = """
            {
              "error": {
                "code": "PRO_REQUIRED",
                "message": "この機能を利用するには隠者プラン（Pro）が必要です。",
                "details": {
                  "field": "hide_watermark"
                }
              }
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        do {
            _ = try await client.createSession(
                CreateSessionRequest(
                    userUUID: "550e8400-e29b-41d4-a716-446655440000",
                    durationMinutes: 30,
                    themeID: "misty_mountain",
                    cardStyle: "washi_classic",
                    hideWatermark: true,
                    isPublic: true,
                    isCustomMessage: false,
                    displayName: nil,
                    message: nil,
                    timezone: "Asia/Tokyo"
                )
            )
            XCTFail("Expected PRO_REQUIRED error")
        } catch let error as APIError {
            XCTAssertTrue(error.isProRequired)
            XCTAssertFalse(error.isContentPolicyViolation)
            XCTAssertEqual(
                error,
                .serverError(
                    statusCode: 403,
                    code: "PRO_REQUIRED",
                    message: "この機能を利用するには隠者プラン（Pro）が必要です。",
                    field: "hide_watermark"
                )
            )
        }
    }

    func testNetworkFailureMapsToAPIErrorNetworkError() async throws {
        let host = self.host!
        URLProtocolStubStorage.shared.register(host: host) { _, _ in
            throw URLError(.timedOut)
        }

        do {
            _ = try await client.fetchActiveStats()
            XCTFail("Expected networkError")
        } catch let error as APIError {
            guard case .networkError = error else {
                return XCTFail("Expected networkError, got \(error)")
            }
            XCTAssertFalse(error.isPermanentFinishFailure)
        }
    }
}
