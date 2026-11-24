import Foundation
import Observation
import SwiftData

/// Snapshot summary presented on S-04 (completed) and S-05 (canceled / interrupted).
struct SessionResultSummary: Equatable, Sendable {
    let status: SessionStatus
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Int
    let theme: ThemeID
    let startedAt: Date
    let plannedEndsAt: Date
    let finishedAt: Date
}

/// Top-level session state machine matching `docs/03-architecture/ios-app-spec.md` §2.
enum AppSessionState: Equatable, Sendable {
    case idle
    case preparingShare
    case active
    case gracePeriod(deadline: Date)
    case completed(SessionResultSummary)
    case canceled(SessionResultSummary)
    case interrupted(SessionResultSummary)

    var isDetoxScreenVisible: Bool {
        switch self {
        case .active, .gracePeriod:
            return true
        default:
            return false
        }
    }
}

/// Central `@Observable` store coordinating timer, lifecycle monitoring, audio, notifications, and SwiftData.
@Observable
@MainActor
final class DetoxSessionStore {
    private let clock: any ClockProviding
    let timerEngine: DetoxTimerEngine
    let lifecycleMonitor: AppLifecycleMonitor
    private let audioManager: any AmbientAudioManaging
    private let notificationScheduler: any NotificationScheduling
    private let repository: any DetoxSessionPersisting
    let preferences: UserPreferencesStore
    let userIDProvider: any AnonymousUserIDProviding
    private let idleTimerController: any IdleTimerControlling

    private var currentRecord: DetoxSessionRecord?

    private(set) var state: AppSessionState = .idle
    private(set) var cumulativeSummary: DetoxCumulativeSummary = .empty
    private(set) var isAudioMuted: Bool = false
    private(set) var activeTheme: ThemeID = .mistyMountain
    private(set) var activeSound: SoundID = .rain
    private(set) var activePlannedEndsAt: Date?
    private(set) var isPro: Bool = false

    /// Active participants excluding self (`nil` or `0` renders serene fallback copy).
    var othersActiveCount: Int? = nil

    var anonymousUserUUID: String {
        userIDProvider.getOrCreateAnonymousUserUUID()
    }

    init(
        clock: any ClockProviding = SystemClock(),
        timerEngine: DetoxTimerEngine,
        lifecycleMonitor: AppLifecycleMonitor,
        audioManager: any AmbientAudioManaging,
        notificationScheduler: any NotificationScheduling,
        repository: any DetoxSessionPersisting,
        preferences: UserPreferencesStore,
        userIDProvider: any AnonymousUserIDProviding = KeychainHelper(),
        idleTimerController: any IdleTimerControlling = UIApplicationIdleTimerController()
    ) {
        self.clock = clock
        self.timerEngine = timerEngine
        self.lifecycleMonitor = lifecycleMonitor
        self.audioManager = audioManager
        self.notificationScheduler = notificationScheduler
        self.repository = repository
        self.preferences = preferences
        self.userIDProvider = userIDProvider
        self.idleTimerController = idleTimerController

        self.activeTheme = preferences.selectedTheme
        self.activeSound = preferences.selectedSound

        bindCallbacks()
        refreshCumulativeSummary()
    }

    convenience init(modelContext: ModelContext) {
        let clock = SystemClock()
        let scheduler = AsyncTimerScheduler()
        let preferences = UserPreferencesStore()
        let timerEngine = DetoxTimerEngine(clock: clock, scheduler: scheduler)
        let lifecycleMonitor = AppLifecycleMonitor(clock: clock, scheduler: scheduler)
        let audioManager = AmbientAudioManager(scheduler: scheduler)
        let notificationScheduler = NotificationScheduler(preferences: preferences, clock: clock)
        let repository = SwiftDataSessionRepository(modelContext: modelContext)

        self.init(
            clock: clock,
            timerEngine: timerEngine,
            lifecycleMonitor: lifecycleMonitor,
            audioManager: audioManager,
            notificationScheduler: notificationScheduler,
            repository: repository,
            preferences: preferences
        )
    }

    // MARK: - Home & Pre-Session Actions

    func updateProStatus(_ newIsPro: Bool) {
        isPro = newIsPro
        preferences.applyEntitlementFallback(isPro: newIsPro)
    }

    func previewSound(_ sound: SoundID) {
        audioManager.playPreview(sound: sound)
    }

    func stopSoundPreview() {
        audioManager.stopPreview()
    }

    func openSharePreparation() {
        audioManager.stopPreview()
        lifecycleMonitor.setMonitoringEnabled(false)
        idleTimerController.isIdleTimerDisabled = false
        state = .preparingShare
    }

    func cancelSharePreparation() {
        lifecycleMonitor.setMonitoringEnabled(false)
        idleTimerController.isIdleTimerDisabled = false
        state = .idle
    }

    /// Computes effective duration in minutes based on current home selection (`untilMorning` or fixed/custom).
    func resolvedSelectedDurationMinutes() -> Int {
        if preferences.selectedDurationIsMorning {
            return MorningTargetCalculator.calculate(
                now: clock.now,
                morningTargetMinutes: preferences.morningTargetMinutes
            ).durationMinutes
        }
        return preferences.durationMinutes
    }

    func beginQuietSessionWithNotificationPrompt() async {
        _ = await notificationScheduler.requestAuthorizationIfNeeded()
        startSession(durationMinutes: resolvedSelectedDurationMinutes(), isPublic: false)
    }

    func startSessionFromShareSheet(
        durationMinutes: Int,
        isPublic: Bool,
        displayName: String? = nil,
        customMessage: String? = nil
    ) async {
        _ = await notificationScheduler.requestAuthorizationIfNeeded()
        startSession(
            durationMinutes: durationMinutes,
            isPublic: isPublic,
            displayName: displayName,
            customMessage: customMessage
        )
    }

    func startSession(
        durationMinutes: Int,
        isPublic: Bool,
        displayName: String? = nil,
        customMessage: String? = nil
    ) {
        audioManager.stopPreview()

        let clampedMinutes = min(
            AppConfig.maxDurationMinutes,
            max(AppConfig.minDurationMinutes, durationMinutes)
        )
        let resolvedTheme = ThemeID.resolved(rawValue: preferences.themeIDRaw, isPro: isPro)
        let resolvedSound = SoundID.resolved(rawValue: preferences.soundIDRaw, isPro: isPro)
        let resolvedPurpose = PurposeID.resolved(rawValue: preferences.purposeIDRaw, isPro: isPro)
        let resolvedCardStyle = CardStyle.resolved(rawValue: preferences.cardStyleRaw, isPro: isPro)

        let startedAt = clock.now
        let plannedDurationSeconds = clampedMinutes * 60
        let plannedEndsAt = startedAt.addingTimeInterval(TimeInterval(plannedDurationSeconds))

        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDisplayName = (trimmedDisplayName?.isEmpty == false) ? trimmedDisplayName : nil
        let resolvedMessage: String? = {
            if let customMessage, !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return resolvedPurpose.presetMessage
        }()

        let record = DetoxSessionRecord(
            localID: UUID(),
            remoteID: nil,
            ownerToken: nil,
            isPublic: isPublic,
            purposeID: resolvedPurpose.rawValue,
            displayName: storedDisplayName,
            customMessage: resolvedMessage,
            themeID: resolvedTheme.rawValue,
            soundID: resolvedSound.rawValue,
            cardStyle: resolvedCardStyle.rawValue,
            plannedDurationSeconds: plannedDurationSeconds,
            actualDurationSeconds: 0,
            statusRaw: SessionStatus.active.rawValue,
            startedAt: startedAt,
            plannedEndsAt: plannedEndsAt,
            finishedAt: nil,
            needsRemoteFinishSync: false
        )

        do {
            try repository.insert(record)
            try repository.save()
        } catch {
            // Local timer must never fail to start even if persistence throws unexpectedly.
        }

        currentRecord = record
        activeTheme = resolvedTheme
        activeSound = resolvedSound
        activePlannedEndsAt = plannedEndsAt
        isAudioMuted = false

        preferences.lastBackgroundWasScreenLock = false
        preferences.activeGraceDeadline = nil

        state = .active
        idleTimerController.isIdleTimerDisabled = preferences.keepScreenOn

        timerEngine.start(startedAt: startedAt, plannedEndsAt: plannedEndsAt)
        audioManager.play(sound: resolvedSound)
        notificationScheduler.scheduleCompletionNotification(
            sessionID: record.localID,
            endsAt: plannedEndsAt
        )
        lifecycleMonitor.setMonitoringEnabled(true)
    }

    // MARK: - In-Session Controls

    func toggleAudioMute() {
        guard activeSound != .none else { return }
        if isAudioMuted {
            isAudioMuted = false
            audioManager.play(sound: activeSound)
        } else {
            isAudioMuted = true
            audioManager.stopImmediately()
        }
    }

    func toggleKeepScreenOn() {
        preferences.keepScreenOn.toggle()
        if state == .active {
            idleTimerController.isIdleTimerDisabled = preferences.keepScreenOn
        }
    }

    func confirmEarlyCancel() {
        finalizeCurrentSession(as: .canceled, finishedAt: clock.now)
    }

    // MARK: - Result Actions

    func retryWithLastSettings() {
        let retryDurationMinutes: Int
        switch state {
        case .canceled(let summary), .interrupted(let summary), .completed(let summary):
            retryDurationMinutes = max(AppConfig.minDurationMinutes, summary.plannedDurationSeconds / 60)
        default:
            retryDurationMinutes = resolvedSelectedDurationMinutes()
        }
        startSession(durationMinutes: retryDurationMinutes, isPublic: false)
    }

    func returnToHome() {
        lifecycleMonitor.setMonitoringEnabled(false)
        timerEngine.reset()
        audioManager.stopImmediately()
        idleTimerController.isIdleTimerDisabled = false
        currentRecord = nil
        activePlannedEndsAt = nil
        isAudioMuted = false
        state = .idle
        refreshCumulativeSummary()
    }

    func dismissProMilestoneBanner() {
        preferences.hasDismissedProBanner = true
    }

    var shouldShowMilestoneProBanner: Bool {
        !isPro
            && !preferences.hasDismissedProBanner
            && cumulativeSummary.completedCount >= AppConfig.proBannerCompletionThreshold
    }

    // MARK: - Scene Lifecycle & Task-Kill Recovery

    func handleScenePhaseChange(_ phase: AppScenePhase) {
        lifecycleMonitor.handleScenePhaseChange(phase)

        // When returning active from screen lock (not grace-expired), re-evaluate completion immediately.
        if phase == .active, state == .active {
            timerEngine.refresh()
        }
    }

    /// Restores or finalizes an active/gracePeriod session after unexpected termination (`ios-app-spec.md` §4).
    func recoverInProgressSessionIfNeeded() {
        guard currentRecord == nil else { return }
        guard let record = try? repository.fetchLatestInProgress() else { return }

        let wasScreenLock = preferences.lastBackgroundWasScreenLock
        preferences.lastBackgroundWasScreenLock = false
        preferences.activeGraceDeadline = nil

        let now = clock.now
        let theme = ThemeID.resolved(rawValue: record.themeID, isPro: isPro)
        let sound = SoundID.resolved(rawValue: record.soundID, isPro: isPro)

        if record.status == .active && now >= record.plannedEndsAt {
            record.status = .completed
            record.actualDurationSeconds = record.plannedDurationSeconds
            record.finishedAt = record.plannedEndsAt
            record.needsRemoteFinishSync = (record.remoteID != nil)
            try? repository.save()

            notificationScheduler.cancelCompletionNotification(sessionID: record.localID)
            notificationScheduler.cancelGraceWarningNotification()
            idleTimerController.isIdleTimerDisabled = false
            activeTheme = theme
            activeSound = sound
            refreshCumulativeSummary()

            let summary = SessionResultSummary(
                status: .completed,
                plannedDurationSeconds: record.plannedDurationSeconds,
                actualDurationSeconds: record.plannedDurationSeconds,
                theme: theme,
                startedAt: record.startedAt,
                plannedEndsAt: record.plannedEndsAt,
                finishedAt: record.plannedEndsAt
            )
            state = .completed(summary)
            return
        }

        if record.status == .active && now < record.plannedEndsAt && wasScreenLock {
            currentRecord = record
            activeTheme = theme
            activeSound = sound
            activePlannedEndsAt = record.plannedEndsAt
            isAudioMuted = false
            state = .active
            idleTimerController.isIdleTimerDisabled = preferences.keepScreenOn

            timerEngine.start(startedAt: record.startedAt, plannedEndsAt: record.plannedEndsAt)
            audioManager.play(sound: sound)
            notificationScheduler.scheduleCompletionNotification(
                sessionID: record.localID,
                endsAt: record.plannedEndsAt
            )
            lifecycleMonitor.setMonitoringEnabled(true)
            return
        }

        let actualSeconds = min(
            record.plannedDurationSeconds,
            max(0, Int(now.timeIntervalSince(record.startedAt)))
        )
        record.status = .interrupted
        record.actualDurationSeconds = actualSeconds
        record.finishedAt = now
        record.needsRemoteFinishSync = (record.remoteID != nil)
        try? repository.save()

        notificationScheduler.cancelCompletionNotification(sessionID: record.localID)
        notificationScheduler.cancelGraceWarningNotification()
        idleTimerController.isIdleTimerDisabled = false
        activeTheme = theme
        activeSound = sound
        refreshCumulativeSummary()

        let summary = SessionResultSummary(
            status: .interrupted,
            plannedDurationSeconds: record.plannedDurationSeconds,
            actualDurationSeconds: actualSeconds,
            theme: theme,
            startedAt: record.startedAt,
            plannedEndsAt: record.plannedEndsAt,
            finishedAt: now
        )
        state = .interrupted(summary)
    }

    func refreshCumulativeSummary() {
        cumulativeSummary = (try? repository.fetchSummary()) ?? .empty
    }

    func fetchRecentHistoryRecords(limitDays: Int = AppConfig.freeHistoryRetentionDays) -> [DetoxSessionRecord] {
        if isPro {
            return (try? repository.fetchAllRecords()) ?? []
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -limitDays, to: clock.now) ?? clock.now
        return (try? repository.fetchRecentRecords(since: cutoff)) ?? []
    }

    func countLockedHistoryRecords(limitDays: Int = AppConfig.freeHistoryRetentionDays) -> Int {
        guard !isPro else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -limitDays, to: clock.now) ?? clock.now
        return (try? repository.countOlderRecords(before: cutoff)) ?? 0
    }

    // MARK: - Private Wiring

    private func bindCallbacks() {
        timerEngine.onCompleted = { [weak self] in
            self?.handleTimerCompleted()
        }
        lifecycleMonitor.onScreenLockConfirmed = { [weak self] in
            self?.preferences.lastBackgroundWasScreenLock = true
        }
        lifecycleMonitor.onEnterGracePeriod = { [weak self] deadline in
            self?.handleEnterGracePeriod(deadline: deadline)
        }
        lifecycleMonitor.onReturnWithinGracePeriod = { [weak self] in
            self?.handleReturnWithinGracePeriod()
        }
        lifecycleMonitor.onGracePeriodExpired = { [weak self] in
            self?.handleGracePeriodExpired()
        }
        lifecycleMonitor.onReturnedActive = { [weak self] _ in
            guard let self else { return }
            self.preferences.lastBackgroundWasScreenLock = false
            if self.state == .active {
                self.timerEngine.refresh()
            }
        }
    }

    private func handleTimerCompleted() {
        // If already interrupted by grace period expiry, keep interrupted precedence.
        if case .interrupted = state { return }
        guard state == .active else { return }
        finalizeCurrentSession(as: .completed, finishedAt: clock.now)
    }

    private func handleEnterGracePeriod(deadline: Date) {
        guard state == .active, let record = currentRecord else { return }
        record.status = .gracePeriod
        try? repository.save()

        preferences.lastBackgroundWasScreenLock = false
        preferences.activeGraceDeadline = deadline
        state = .gracePeriod(deadline: deadline)
        notificationScheduler.scheduleGraceWarningNotification()
    }

    private func handleReturnWithinGracePeriod() {
        guard case .gracePeriod = state, let record = currentRecord else { return }
        record.status = .active
        try? repository.save()

        preferences.activeGraceDeadline = nil
        state = .active
        notificationScheduler.cancelGraceWarningNotification()
        timerEngine.refresh()
    }

    private func handleGracePeriodExpired() {
        switch state {
        case .active, .gracePeriod:
            finalizeCurrentSession(as: .interrupted, finishedAt: clock.now)
        default:
            break
        }
    }

    private func finalizeCurrentSession(as status: SessionStatus, finishedAt: Date) {
        guard let record = currentRecord else { return }

        lifecycleMonitor.setMonitoringEnabled(false)
        timerEngine.stop()
        idleTimerController.isIdleTimerDisabled = false
        preferences.lastBackgroundWasScreenLock = false
        preferences.activeGraceDeadline = nil

        notificationScheduler.cancelCompletionNotification(sessionID: record.localID)
        notificationScheduler.cancelGraceWarningNotification()
        audioManager.stopWithFadeOut()

        let actualSeconds: Int
        if status == .completed {
            actualSeconds = record.plannedDurationSeconds
        } else {
            actualSeconds = min(
                record.plannedDurationSeconds,
                max(0, Int(finishedAt.timeIntervalSince(record.startedAt)))
            )
        }

        record.status = status
        record.actualDurationSeconds = actualSeconds
        record.finishedAt = finishedAt
        record.needsRemoteFinishSync = (record.remoteID != nil)
        try? repository.save()

        let theme = ThemeID.resolved(rawValue: record.themeID, isPro: isPro)
        let summary = SessionResultSummary(
            status: status,
            plannedDurationSeconds: record.plannedDurationSeconds,
            actualDurationSeconds: actualSeconds,
            theme: theme,
            startedAt: record.startedAt,
            plannedEndsAt: record.plannedEndsAt,
            finishedAt: finishedAt
        )

        currentRecord = nil
        activePlannedEndsAt = nil
        isAudioMuted = false
        refreshCumulativeSummary()

        switch status {
        case .completed:
            state = .completed(summary)
        case .canceled:
            state = .canceled(summary)
        default:
            state = .interrupted(summary)
        }
    }
}
