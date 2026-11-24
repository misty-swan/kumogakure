import Foundation
import SwiftData

/// Local SwiftData persistence model matching `docs/03-architecture/database-design.md` §2.1.
@Model
final class DetoxSessionRecord {
    @Attribute(.unique) var localID: UUID
    var remoteID: String?
    var ownerToken: String?
    var isPublic: Bool
    var purposeID: String
    var displayName: String?
    var customMessage: String?
    var themeID: String
    var soundID: String
    var cardStyle: String
    var plannedDurationSeconds: Int
    var actualDurationSeconds: Int
    var statusRaw: String
    var startedAt: Date
    var plannedEndsAt: Date
    var finishedAt: Date?
    var needsRemoteFinishSync: Bool

    init(
        localID: UUID = UUID(),
        remoteID: String? = nil,
        ownerToken: String? = nil,
        isPublic: Bool = false,
        purposeID: String = PurposeID.rest.rawValue,
        displayName: String? = nil,
        customMessage: String? = nil,
        themeID: String = ThemeID.mistyMountain.rawValue,
        soundID: String = SoundID.rain.rawValue,
        cardStyle: String = CardStyle.washiClassic.rawValue,
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int = 0,
        statusRaw: String = SessionStatus.active.rawValue,
        startedAt: Date,
        plannedEndsAt: Date,
        finishedAt: Date? = nil,
        needsRemoteFinishSync: Bool = false
    ) {
        self.localID = localID
        self.remoteID = remoteID
        self.ownerToken = ownerToken
        self.isPublic = isPublic
        self.purposeID = purposeID
        self.displayName = displayName
        self.customMessage = customMessage
        self.themeID = themeID
        self.soundID = soundID
        self.cardStyle = cardStyle
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.statusRaw = statusRaw
        self.startedAt = startedAt
        self.plannedEndsAt = plannedEndsAt
        self.finishedAt = finishedAt
        self.needsRemoteFinishSync = needsRemoteFinishSync
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .interrupted }
        set { statusRaw = newValue.rawValue }
    }
}

/// Cumulative completed session totals shown across both Free and Pro plans.
struct DetoxCumulativeSummary: Equatable, Sendable {
    let totalCompletedSeconds: Int
    let completedCount: Int

    static let empty = DetoxCumulativeSummary(totalCompletedSeconds: 0, completedCount: 0)
}

@MainActor
protocol DetoxSessionPersisting: AnyObject {
    func insert(_ record: DetoxSessionRecord) throws
    func save() throws
    func fetchLatestInProgress() throws -> DetoxSessionRecord?
    func fetchSummary() throws -> DetoxCumulativeSummary
    func fetchRecentRecords(since cutoff: Date) throws -> [DetoxSessionRecord]
    func countOlderRecords(before cutoff: Date) throws -> Int
    func fetchAllRecords() throws -> [DetoxSessionRecord]
    func fetchPendingRemoteFinishRecords() throws -> [DetoxSessionRecord]
}

@MainActor
final class SwiftDataSessionRepository: DetoxSessionPersisting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func insert(_ record: DetoxSessionRecord) throws {
        modelContext.insert(record)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func fetchLatestInProgress() throws -> DetoxSessionRecord? {
        // Bind enum raw values to locals before `#Predicate` because SwiftData predicates cannot invoke `.rawValue`.
        let activeRaw = SessionStatus.active.rawValue
        let graceRaw = SessionStatus.gracePeriod.rawValue
        var descriptor = FetchDescriptor<DetoxSessionRecord>(
            predicate: #Predicate { $0.statusRaw == activeRaw || $0.statusRaw == graceRaw },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchSummary() throws -> DetoxCumulativeSummary {
        let completedRaw = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<DetoxSessionRecord>(
            predicate: #Predicate { $0.statusRaw == completedRaw }
        )
        let records = try modelContext.fetch(descriptor)
        let totalSeconds = records.reduce(0) { $0 + max(0, $1.actualDurationSeconds) }
        return DetoxCumulativeSummary(
            totalCompletedSeconds: totalSeconds,
            completedCount: records.count
        )
    }

    func fetchRecentRecords(since cutoff: Date) throws -> [DetoxSessionRecord] {
        let descriptor = FetchDescriptor<DetoxSessionRecord>(
            predicate: #Predicate { $0.startedAt >= cutoff },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func countOlderRecords(before cutoff: Date) throws -> Int {
        let descriptor = FetchDescriptor<DetoxSessionRecord>(
            predicate: #Predicate { $0.startedAt < cutoff }
        )
        return try modelContext.fetchCount(descriptor)
    }

    func fetchAllRecords() throws -> [DetoxSessionRecord] {
        let descriptor = FetchDescriptor<DetoxSessionRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchPendingRemoteFinishRecords() throws -> [DetoxSessionRecord] {
        let descriptor = FetchDescriptor<DetoxSessionRecord>(
            predicate: #Predicate { $0.needsRemoteFinishSync == true },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}
