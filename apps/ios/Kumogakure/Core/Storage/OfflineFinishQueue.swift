import Foundation

@MainActor
protocol OfflineFinishQueuing: AnyObject {
    func submitFinish(for record: DetoxSessionRecord) async
    func flushPendingFinishes() async
}

/// Reliably syncs finished/canceled/interrupted sessions to `/api/v1/sessions/{id}/finish`.
/// Pending items are persisted in SwiftData and retried on launch and foreground return.
@MainActor
final class OfflineFinishQueue: OfflineFinishQueuing {
    private let apiClient: any KumogakureAPIClienting
    private let repository: any DetoxSessionPersisting
    private let clock: any ClockProviding
    private var isFlushing = false

    init(
        apiClient: any KumogakureAPIClienting,
        repository: any DetoxSessionPersisting,
        clock: any ClockProviding = SystemClock()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.clock = clock
    }

    func submitFinish(for record: DetoxSessionRecord) async {
        guard !record.status.isInProgress else { return }

        guard let remoteID = record.remoteID, !remoteID.isEmpty,
              let ownerToken = record.ownerToken, !ownerToken.isEmpty else {
            record.needsRemoteFinishSync = false
            record.ownerToken = nil
            try? repository.save()
            return
        }

        let expiresAt = record.startedAt.addingTimeInterval(AppConfig.sessionTTLSeconds)
        guard clock.now < expiresAt else {
            // Expired past the 24-hour server TTL: discard without pointless network traffic.
            record.needsRemoteFinishSync = false
            record.ownerToken = nil
            try? repository.save()
            return
        }

        let outcome: RemoteFinishOutcome = (record.status == .completed) ? .completed : .canceled

        do {
            _ = try await apiClient.finishSession(
                id: remoteID,
                ownerToken: ownerToken,
                outcome: outcome
            )
            record.needsRemoteFinishSync = false
            record.ownerToken = nil
            try? repository.save()
        } catch let apiError as APIError where apiError.isPermanentFinishFailure {
            record.needsRemoteFinishSync = false
            record.ownerToken = nil
            try? repository.save()
        } catch {
            // Keep `ownerToken` and retry flag intact for next launch / foreground return.
            record.needsRemoteFinishSync = true
            try? repository.save()
        }
    }

    func flushPendingFinishes() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let pending = (try? repository.fetchPendingRemoteFinishRecords()) ?? []
        for record in pending {
            await submitFinish(for: record)
        }
    }
}
