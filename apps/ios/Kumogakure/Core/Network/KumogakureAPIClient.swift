import Foundation

// MARK: - Request / Response DTOs (`docs/03-architecture/api-spec.md`)

struct CreateSessionRequest: Codable, Equatable, Sendable {
    let userUUID: String
    let durationMinutes: Int
    let themeID: String
    let cardStyle: String
    let hideWatermark: Bool
    let isPublic: Bool
    let isCustomMessage: Bool
    let displayName: String?
    let message: String?
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case userUUID = "user_uuid"
        case durationMinutes = "duration_minutes"
        case themeID = "theme_id"
        case cardStyle = "card_style"
        case hideWatermark = "hide_watermark"
        case isPublic = "is_public"
        case isCustomMessage = "is_custom_message"
        case displayName = "display_name"
        case message
        case timezone
    }
}

struct CreateSessionResponse: Codable, Equatable, Sendable {
    let id: String
    let ownerToken: String
    let status: String
    let startedAt: Int64
    let endsAt: Int64
    let expiresAt: Int64
    let shareURL: String?
    let ogpImageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerToken = "owner_token"
        case status
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case expiresAt = "expires_at"
        case shareURL = "share_url"
        case ogpImageURL = "ogp_image_url"
    }
}

enum RemoteFinishOutcome: String, Codable, Equatable, Sendable {
    case completed = "completed"
    case canceled = "canceled"
}

struct FinishSessionRequest: Codable, Equatable, Sendable {
    let outcome: RemoteFinishOutcome
}

struct FinishSessionResponse: Codable, Equatable, Sendable {
    let id: String
    let status: String
    let finishedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case finishedAt = "finished_at"
    }
}

struct ActiveStatsResponse: Codable, Equatable, Sendable {
    let activeCount: Int
    let sampledAt: Int64

    enum CodingKeys: String, CodingKey {
        case activeCount = "active_count"
        case sampledAt = "sampled_at"
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError, Equatable, Sendable {
    case serverError(statusCode: Int, code: String, message: String, field: String?)
    case httpError(statusCode: Int)
    case networkError(description: String)
    case decodingError(description: String)
    case invalidResponse

    var isProRequired: Bool {
        if case .serverError(_, let code, _, _) = self {
            return code == "PRO_REQUIRED"
        }
        return false
    }

    var isContentPolicyViolation: Bool {
        if case .serverError(_, let code, _, _) = self {
            return code == "CONTENT_POLICY_VIOLATION"
        }
        return false
    }

    /// Permanent 4xx rejections where re-sending `/finish` would never succeed.
    var isPermanentFinishFailure: Bool {
        switch self {
        case .serverError(let statusCode, _, _, _), .httpError(let statusCode):
            return [400, 401, 404, 410, 422].contains(statusCode)
        case .networkError, .decodingError, .invalidResponse:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .serverError(_, _, let message, _):
            return message
        case .httpError(let statusCode):
            return "サーバーとの通信に失敗しました（\(statusCode)）。"
        case .networkError:
            return "通信環境をご確認のうえ、もう一度お試しください。"
        case .decodingError:
            return "サーバー応答の形式を読み取れませんでした。"
        case .invalidResponse:
            return "予期しない応答を受信しました。"
        }
    }
}

private struct ErrorEnvelopeDTO: Decodable {
    struct Body: Decodable {
        struct Details: Decodable {
            let field: String?
        }

        let code: String
        let message: String
        let details: Details?
    }

    let error: Body
}

// MARK: - Client Protocol & Implementation

protocol KumogakureAPIClienting: Sendable {
    func createSession(_ request: CreateSessionRequest) async throws -> CreateSessionResponse
    func finishSession(
        id: String,
        ownerToken: String,
        outcome: RemoteFinishOutcome
    ) async throws -> FinishSessionResponse
    func fetchActiveStats() async throws -> ActiveStatsResponse
}

/// URLSession-based API client with 5-second request timeout for graceful offline degradation.
final class KumogakureAPIClient: KumogakureAPIClienting, Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = AppConfig.apiRequestTimeoutSeconds
            configuration.timeoutIntervalForResource = AppConfig.apiResourceTimeoutSeconds
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func createSession(_ request: CreateSessionRequest) async throws -> CreateSessionResponse {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("sessions")
        return try await sendJSONRequest(
            url: url,
            method: "POST",
            bearerToken: nil,
            body: request,
            expectedStatusCodes: [200, 201]
        )
    }

    func finishSession(
        id: String,
        ownerToken: String,
        outcome: RemoteFinishOutcome
    ) async throws -> FinishSessionResponse {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("sessions")
            .appendingPathComponent(id)
            .appendingPathComponent("finish")
        return try await sendJSONRequest(
            url: url,
            method: "POST",
            bearerToken: ownerToken,
            body: FinishSessionRequest(outcome: outcome),
            expectedStatusCodes: [200]
        )
    }

    func fetchActiveStats() async throws -> ActiveStatsResponse {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("stats")
            .appendingPathComponent("active")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConfig.apiRequestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request: request, expectedStatusCodes: [200])
    }

    // MARK: - Private Helpers

    private func sendJSONRequest<Body: Encodable, ResponseBody: Decodable>(
        url: URL,
        method: String,
        bearerToken: String?,
        body: Body,
        expectedStatusCodes: Set<Int>
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = AppConfig.apiRequestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return try await execute(request: request, expectedStatusCodes: expectedStatusCodes)
    }

    private func execute<ResponseBody: Decodable>(
        request: URLRequest,
        expectedStatusCodes: Set<Int>
    ) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(description: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(ErrorEnvelopeDTO.self, from: data) {
                throw APIError.serverError(
                    statusCode: httpResponse.statusCode,
                    code: envelope.error.code,
                    message: envelope.error.message,
                    field: envelope.error.details?.field
                )
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw APIError.decodingError(description: error.localizedDescription)
        }
    }
}
