import Foundation
import Observation
import SwiftData
import UserNotifications

/// Snapshot summary presented on S-04 (completed) and S-05 (canceled / interrupted).
struct SessionResultSummary: Equatable, Sendable {
    let status: SessionStatus
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Int
    let theme: ThemeID
    let cardStyle: CardStyle
    let hideWatermark: Bool
    let displayName: String?
    let message: String?
    let startedAt: Date
    let plannedEndsAt: Date
    let finishedAt: Date

    init(
        status: SessionStatus,
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int,
        theme: ThemeID,
        cardStyle: CardStyle = .washiClassic,
        hideWatermark: Bool = false,
        displayName: String? = nil,
        message: String? = nil,
        startedAt: Date,
        plannedEndsAt: Date,
        finishedAt: Date
    ) {
        self.status = status
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.theme = theme
        self.cardStyle = cardStyle
        self.hideWatermark = hideWatermark
        self.displayName = displayName
        self.message = message
        self.startedAt = startedAt
        self.plannedEndsAt = plannedEndsAt
        self.finishedAt = finishedAt
    }
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

/// Central `@Observable` store coordinating timer, lifecycle monitoring, audio, notifications, API sync, billing, and SwiftData.
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
    private let apiClient: any KumogakureAPIClienting
    private let offlineFinishQueue: any OfflineFinishQueuing
    let subscriptionManager: SubscriptionManager

    private var currentRecord: DetoxSessionRecord?
    private var activeCustomHideWatermark: Bool?
    private var hasStartedAppLaunch = false
    private var pendingBackgroundSyncTask: Task<Void, Never>?

    private(set) var state: AppSessionState = .idle
    private(set) var cumulativeSummary: DetoxCumulativeSummary = .empty
    private(set) var isAudioMuted: Bool = false
    private(set) var activeTheme: ThemeID = .mistyMountain
    private(set) var activeSound: SoundID = .rain
    private(set) var activePlannedEndsAt: Date?
    private(set) var isPro: Bool = false

    private(set) var lastFetchedServerActiveCount: Int? = nil
    private(set) var hasActiveRemoteSession: Bool = false

    /// Active participants excluding self (`nil` or `0` renders serene fallback copy).
    var othersActiveCount: Int? {
        get {
            guard let raw = lastFetchedServerActiveCount else { return nil }
            return hasActiveRemoteSession ? max(0, raw - 1) : max(0, raw)
        }
        set {
            lastFetchedServerActiveCount = newValue
            hasActiveRemoteSession = false
        }
    }

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
        idleTimerController: any IdleTimerControlling = UIApplicationIdleTimerController(),
        apiClient: (any KumogakureAPIClienting)? = nil,
        offlineFinishQueue: (any OfflineFinishQueuing)? = nil,
        subscriptionManager: SubscriptionManager? = nil
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

        let resolvedAPIClient = apiClient ?? KumogakureAPIClient()
        self.apiClient = resolvedAPIClient
        self.offlineFinishQueue = offlineFinishQueue ?? OfflineFinishQueue(
            apiClient: resolvedAPIClient,
            repository: repository,
            clock: clock
        )
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()

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
        let apiClient = KumogakureAPIClient()
        let offlineFinishQueue = OfflineFinishQueue(
            apiClient: apiClient,
            repository: repository,
            clock: clock
        )
        let subscriptionManager = SubscriptionManager()

        self.init(
            clock: clock,
            timerEngine: timerEngine,
            lifecycleMonitor: lifecycleMonitor,
            audioManager: audioManager,
            notificationScheduler: notificationScheduler,
            repository: repository,
            preferences: preferences,
            apiClient: apiClient,
            offlineFinishQueue: offlineFinishQueue,
            subscriptionManager: subscriptionManager
        )
    }

    // MARK: - App Launch & Networking

    /// Runs initial recovery, StoreKit entitlement sync, pending `/finish` retry, and active count fetch.
    func onAppLaunch() async {
        recoverInProgressSessionIfNeeded()
        if !hasStartedAppLaunch {
            hasStartedAppLaunch = true
            await subscriptionManager.start(appUserID: anonymousUserUUID)
        } else {
            await subscriptionManager.refreshEntitlement()
        }
        await offlineFinishQueue.flushPendingFinishes()
        await refreshActiveParticipants()
    }

    func refreshActiveParticipants() async {
        do {
            let stats = try await apiClient.fetchActiveStats()
            lastFetchedServerActiveCount = max(0, stats.activeCount)
        } catch {
            // Keep cached count or nil (`NFR-004` / `FR-006`: never surface an error dialog).
        }
    }

    func awaitPendingBackgroundSync() async {
        await pendingBackgroundSyncTask?.value
    }

    // MARK: - Entitlement & Home Pre-Session Actions

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

    func createPublicRemoteSession(
        durationMinutes: Int,
        displayName: String?,
        message: String?,
        isCustomMessage: Bool,
        cardStyle: CardStyle,
        hideWatermark: Bool
    ) async throws -> CreateSessionResponse {
        let clampedMinutes = min(
            AppConfig.maxDurationMinutes,
            max(AppConfig.minDurationMinutes, durationMinutes)
        )
        let resolvedTheme = ThemeID.resolved(rawValue: preferences.themeIDRaw, isPro: isPro)
        let resolvedCardStyle = CardStyle.resolved(rawValue: cardStyle.rawValue, isPro: isPro)
        let effectiveCustomMessage = isCustomMessage && isPro
        let effectiveHideWatermark = hideWatermark && isPro

        let sanitizedName = TextInputLimiter.sanitizedOptional(
            displayName,
            limit: AppConfig.maxDisplayNameLength
        )
        let sanitizedMessage = TextInputLimiter.sanitizedOptional(
            message,
            limit: AppConfig.maxMessageLength
        )

        let request = CreateSessionRequest(
            userUUID: anonymousUserUUID,
            durationMinutes: clampedMinutes,
            themeID: resolvedTheme.rawValue,
            cardStyle: resolvedCardStyle.rawValue,
            hideWatermark: effectiveHideWatermark,
            isPublic: true,
            isCustomMessage: effectiveCustomMessage,
            displayName: sanitizedName,
            message: sanitizedMessage,
            timezone: TimeZone.current.identifier
        )
        return try await apiClient.createSession(request)
    }

    func beginQuietSessionWithNotificationPrompt() async {
        _ = await notificationScheduler.requestAuthorizationIfNeeded()
        startSession(durationMinutes: resolvedSelectedDurationMinutes(), isPublic: false)
    }

    func startSessionFromShareSheet(
        durationMinutes: Int,
        isPublic: Bool,
        displayName: String? = nil,
        customMessage: String? = nil,
        remoteSession: CreateSessionResponse? = nil,
        cardStyle: CardStyle? = nil,
        hideWatermark: Bool? = nil
    ) async {
        _ = await notificationScheduler.requestAuthorizationIfNeeded()
        startSession(
            durationMinutes: durationMinutes,
            isPublic: isPublic,
            displayName: displayName,
            customMessage: customMessage,
            remoteSession: remoteSession,
            cardStyle: cardStyle,
            hideWatermark: hideWatermark
        )
    }

    func startSession(
        durationMinutes: Int,
        isPublic: Bool,
        displayName: String? = nil,
        customMessage: String? = nil,
        remoteSession: CreateSessionResponse? = nil,
        cardStyle: CardStyle? = nil,
        hideWatermark: Bool? = nil
    ) {
        audioManager.stopPreview()

        let clampedMinutes = min(
            AppConfig.maxDurationMinutes,
            max(AppConfig.minDurationMinutes, durationMinutes)
        )
        let resolvedTheme = ThemeID.resolved(rawValue: preferences.themeIDRaw, isPro: isPro)
        let resolvedSound = SoundID.resolved(rawValue: preferences.soundIDRaw, isPro: isPro)
        let resolvedPurpose = PurposeID.resolved(rawValue: preferences.purposeIDRaw, isPro: isPro)
        let requestedStyleRaw = cardStyle?.rawValue ?? preferences.cardStyleRaw
        let resolvedCardStyle = CardStyle.resolved(rawValue: requestedStyleRaw, isPro: isPro)
        let resolvedHideWatermark = (hideWatermark ?? preferences.hideWatermark) && isPro

        let startedAt = clock.now
        let plannedDurationSeconds = clampedMinutes * 60
        let plannedEndsAt = startedAt.addingTimeInterval(TimeInterval(plannedDurationSeconds))

        let storedDisplayName = TextInputLimiter.sanitizedOptional(
            displayName ?? preferences.displayName,
            limit: AppConfig.maxDisplayNameLength
        )
        let resolvedMessage: String? = {
            if let sanitized = TextInputLimiter.sanitizedOptional(
                customMessage,
                limit: AppConfig.maxMessageLength
            ) {
                return sanitized
            }
            return resolvedPurpose.presetMessage
        }()

        let record = DetoxSessionRecord(
            localID: UUID(),
            remoteID: remoteSession?.id,
            ownerToken: remoteSession?.ownerToken,
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
        activeCustomHideWatermark = resolvedHideWatermark
        activeTheme = resolvedTheme
        activeSound = resolvedSound
        activePlannedEndsAt = plannedEndsAt
        isAudioMuted = false
        hasActiveRemoteSession = (remoteSession != nil)

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

        if remoteSession != nil {
            pendingBackgroundSyncTask = Task { [weak self] in
                await self?.refreshActiveParticipants()
            }
        } else if !isPublic {
            pendingBackgroundSyncTask = Task { [weak self] in
                await self?.registerPrivateRemoteSession(
                    for: record,
                    durationMinutes: clampedMinutes,
                    theme: resolvedTheme,
                    cardStyle: resolvedCardStyle
                )
            }
        }
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
        activeCustomHideWatermark = nil
        activePlannedEndsAt = nil
        isAudioMuted = false
        hasActiveRemoteSession = false
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

    // MARK: - Notifications & History Queries

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationScheduler.authorizationStatus()
    }

    func requestNotificationAuthorization() async -> Bool {
        await notificationScheduler.requestAuthorizationIfNeeded()
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

    // MARK: - Scene Lifecycle & Task-Kill Recovery

    func handleScenePhaseChange(_ phase: AppScenePhase) {
        lifecycleMonitor.handleScenePhaseChange(phase)

        // When returning active from screen lock (not grace-expired), re-evaluate completion immediately.
        if phase == .active {
            if state == .active {
                timerEngine.refresh()
            }
            Task { [weak self] in
                guard let self else { return }
                await self.offlineFinishQueue.flushPendingFinishes()
                await self.refreshActiveParticipants()
            }
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
        let cardStyle = CardStyle.resolved(rawValue: record.cardStyle, isPro: isPro)
        let hideWatermark = preferences.hideWatermark && isPro

        if record.status == .active && now >= record.plannedEndsAt {
            record.status = .completed
            record.actualDurationSeconds = record.plannedDurationSeconds
            record.finishedAt = record.plannedEndsAt
            let shouldSync = (record.remoteID != nil && record.ownerToken != nil)
            record.needsRemoteFinishSync = shouldSync
            try? repository.save()

            notificationScheduler.cancelCompletionNotification(sessionID: record.localID)
            notificationScheduler.cancelGraceWarningNotification()
            idleTimerController.isIdleTimerDisabled = false
            activeTheme = theme
            activeSound = sound
            hasActiveRemoteSession = false
            refreshCumulativeSummary()

            let summary = SessionResultSummary(
                status: .completed,
                plannedDurationSeconds: record.plannedDurationSeconds,
                actualDurationSeconds: record.plannedDurationSeconds,
                theme: theme,
                cardStyle: cardStyle,
                hideWatermark: hideWatermark,
                displayName: record.displayName,
                message: record.customMessage,
                startedAt: record.startedAt,
                plannedEndsAt: record.plannedEndsAt,
                finishedAt: record.plannedEndsAt
            )
            state = .completed(summary)

            if shouldSync {
                pendingBackgroundSyncTask = Task { [weak self] in
                    await self?.offlineFinishQueue.submitFinish(for: record)
                }
            }
            return
        }

        if record.status == .active && now < record.plannedEndsAt && wasScreenLock {
            currentRecord = record
            activeTheme = theme
            activeSound = sound
            activePlannedEndsAt = record.plannedEndsAt
            isAudioMuted = false
            hasActiveRemoteSession = (record.remoteID != nil)
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
        let shouldSync = (record.remoteID != nil && record.ownerToken != nil)
        record.needsRemoteFinishSync = shouldSync
        try? repository.save()

        notificationScheduler.cancelCompletionNotification(sessionID: record.localID)
        notificationScheduler.cancelGraceWarningNotification()
        idleTimerController.isIdleTimerDisabled = false
        activeTheme = theme
        activeSound = sound
        hasActiveRemoteSession = false
        refreshCumulativeSummary()

        let summary = SessionResultSummary(
            status: .interrupted,
            plannedDurationSeconds: record.plannedDurationSeconds,
            actualDurationSeconds: actualSeconds,
            theme: theme,
            cardStyle: cardStyle,
            hideWatermark: hideWatermark,
            displayName: record.displayName,
            message: record.customMessage,
            startedAt: record.startedAt,
            plannedEndsAt: record.plannedEndsAt,
            finishedAt: now
        )
        state = .interrupted(summary)

        if shouldSync {
            pendingBackgroundSyncTask = Task { [weak self] in
                await self?.offlineFinishQueue.submitFinish(for: record)
            }
        }
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
        subscriptionManager.onEntitlementChanged = { [weak self] newIsPro in
            self?.updateProStatus(newIsPro)
        }
    }

    private func registerPrivateRemoteSession(
        for record: DetoxSessionRecord,
        durationMinutes: Int,
        theme: ThemeID,
        cardStyle: CardStyle
    ) async {
        let request = CreateSessionRequest(
            userUUID: anonymousUserUUID,
            durationMinutes: durationMinutes,
            themeID: theme.rawValue,
            cardStyle: cardStyle.rawValue,
            hideWatermark: false,
            isPublic: false,
            isCustomMessage: false,
            displayName: nil,
            message: nil,
            timezone: TimeZone.current.identifier
        )

        do {
            let response = try await apiClient.createSession(request)
            record.remoteID = response.id
            record.ownerToken = response.ownerToken

            if record.status.isInProgress, currentRecord?.localID == record.localID {
                hasActiveRemoteSession = true
                try? repository.save()
                await refreshActiveParticipants()
            } else {
                // Session finished locally before the network call returned: immediately send `/finish`.
                record.needsRemoteFinishSync = true
                try? repository.save()
                await offlineFinishQueue.submitFinish(for: record)
            }
        } catch {
            // Silent degradation: local timer & audio continue offline (`NFR-004`).
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

        let shouldSync = (record.remoteID != nil && record.ownerToken != nil)
        record.status = status
        record.actualDurationSeconds = actualSeconds
        record.finishedAt = finishedAt
        record.needsRemoteFinishSync = shouldSync
        try? repository.save()

        let theme = ThemeID.resolved(rawValue: record.themeID, isPro: isPro)
        let cardStyle = CardStyle.resolved(rawValue: record.cardStyle, isPro: isPro)
        let hideWatermark = (activeCustomHideWatermark ?? preferences.hideWatermark) && isPro
        let summary = SessionResultSummary(
            status: status,
            plannedDurationSeconds: record.plannedDurationSeconds,
            actualDurationSeconds: actualSeconds,
            theme: theme,
            cardStyle: cardStyle,
            hideWatermark: hideWatermark,
            displayName: record.displayName,
            message: record.customMessage,
            startedAt: record.startedAt,
            plannedEndsAt: record.plannedEndsAt,
            finishedAt: finishedAt
        )

        currentRecord = nil
        activeCustomHideWatermark = nil
        activePlannedEndsAt = nil
        isAudioMuted = false
        hasActiveRemoteSession = false
        refreshCumulativeSummary()

        switch status {
        case .completed:
            state = .completed(summary)
        case .canceled:
            state = .canceled(summary)
        default:
            state = .interrupted(summary)
        }

        if shouldSync {
            pendingBackgroundSyncTask = Task { [weak self] in
                await self?.offlineFinishQueue.submitFinish(for: record)
            }
        }
    }
}
