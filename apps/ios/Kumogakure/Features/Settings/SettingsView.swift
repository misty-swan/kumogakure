import StoreKit
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// S-08 Settings Screen (`ux-and-screens.md` S-08).
struct SettingsView: View {
    private enum PendingProPreference {
        case theme(ThemeID)
        case sound(SoundID)
        case purposeCustom
    }

    private struct SafariDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Bindable var store: DetoxSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var copiedSupportID = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var pendingProPreference: PendingProPreference?
    @State private var safariDestination: SafariDestination?
    @State private var showRestoreAlert = false

    private var morningOptions: [Int] {
        stride(
            from: AppConfig.minMorningTargetMinutes,
            through: AppConfig.maxMorningTargetMinutes,
            by: AppConfig.morningTargetStepMinutes
        ).map { $0 }
    }

    private var durationOptions: [Int] {
        stride(
            from: AppConfig.minDurationMinutes,
            through: AppConfig.maxDurationMinutes,
            by: AppConfig.durationStepMinutes
        ).map { $0 }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                planSection
                defaultPreferencesSection
                notificationsSection
                supportAndLegalSection
            }
            .scrollContentBackground(.hidden)
            .background(KumogakureColors.sumiBg)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(KumogakureColors.shinonomeAccent)
                }
            }
            .task {
                notificationStatus = await store.notificationAuthorizationStatus()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        notificationStatus = await store.notificationAuthorizationStatus()
                    }
                }
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(store: store, trigger: trigger) {
                    applyPendingProPreference()
                }
            }
            .sheet(item: $safariDestination) { destination in
                SafariWebView(url: destination.url)
                    .ignoresSafeArea()
            }
            .alert("購入の復元", isPresented: $showRestoreAlert) {
                Button("OK") {
                    store.subscriptionManager.clearMessages()
                }
            } message: {
                Text(store.subscriptionManager.restoreMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var planSection: some View {
        Section("プラン") {
            HStack {
                Text("現在のプラン")
                Spacer()
                Text(store.isPro ? "隠者（Pro）" : "旅人（無料）")
                    .foregroundStyle(KumogakureColors.shinonomeAccent)
            }

            if let expiration = store.subscriptionManager.entitlement.expirationDate, store.isPro {
                HStack {
                    Text("有効期限")
                    Spacer()
                    Text(expiration.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }

            if store.isPro {
                Button("サブスクリプションを管理") {
                    Task {
                        await openManageSubscriptions()
                    }
                }
                .foregroundStyle(KumogakureColors.washiText)
            } else {
                Button("隠者プラン（Pro）を見る") {
                    paywallTrigger = .settingsUpgrade
                }
                .foregroundStyle(KumogakureColors.shinonomeAccent)
            }

            Button("購入を復元") {
                Task {
                    _ = await store.subscriptionManager.restorePurchases()
                    if store.subscriptionManager.restoreMessage != nil {
                        showRestoreAlert = true
                    }
                }
            }
            .foregroundStyle(KumogakureColors.washiText)
        }
    }

    private var defaultPreferencesSection: some View {
        Section("デフォルト設定") {
            Toggle(
                "初期時間を「明日の朝まで」にする",
                isOn: Binding(
                    get: { store.preferences.selectedDurationIsMorning },
                    set: { isMorning in
                        if isMorning {
                            store.preferences.selectUntilMorning()
                        } else {
                            store.preferences.selectPresetDuration(minutes: store.preferences.durationMinutes)
                        }
                    }
                )
            )
            .tint(KumogakureColors.shinonomeAccent)

            if !store.preferences.selectedDurationIsMorning {
                Picker(
                    "初期時間",
                    selection: Binding(
                        get: { store.preferences.durationMinutes },
                        set: { store.preferences.selectPresetDuration(minutes: $0) }
                    )
                ) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text(DurationFormatter.japaneseDuration(minutes: minutes))
                            .tag(minutes)
                    }
                }
            }

            Picker(
                "「明日の朝まで」目標時刻",
                selection: Binding(
                    get: { store.preferences.morningTargetMinutes },
                    set: { store.preferences.morningTargetMinutes = $0 }
                )
            ) {
                ForEach(morningOptions, id: \.self) { minutes in
                    Text(DurationFormatter.morningTargetString(minutesSinceMidnight: minutes))
                        .tag(minutes)
                }
            }

            Picker(
                "初期目的",
                selection: Binding(
                    get: { PurposeID.resolved(rawValue: store.preferences.purposeIDRaw, isPro: store.isPro) },
                    set: { newValue in
                        if newValue.isPro && !store.isPro {
                            pendingProPreference = .purposeCustom
                            paywallTrigger = .purposeCustom
                        } else {
                            store.preferences.selectPurpose(newValue)
                        }
                    }
                )
            ) {
                ForEach(PurposeID.allCases) { purpose in
                    Text(purpose.isPro && !store.isPro ? "\(purpose.displayName)（隠者）" : purpose.displayName)
                        .tag(purpose)
                }
            }

            Picker(
                "初期風景",
                selection: Binding(
                    get: { ThemeID.resolved(rawValue: store.preferences.themeIDRaw, isPro: store.isPro) },
                    set: { newValue in
                        if newValue.isPro && !store.isPro {
                            pendingProPreference = .theme(newValue)
                            paywallTrigger = .theme(newValue)
                        } else {
                            store.preferences.selectTheme(newValue)
                        }
                    }
                )
            ) {
                ForEach(ThemeID.allCases) { theme in
                    Text(theme.isPro && !store.isPro ? "\(theme.displayName)（隠者）" : theme.displayName)
                        .tag(theme)
                }
            }

            Picker(
                "初期環境音",
                selection: Binding(
                    get: { SoundID.resolved(rawValue: store.preferences.soundIDRaw, isPro: store.isPro) },
                    set: { newValue in
                        if newValue.isPro && !store.isPro {
                            pendingProPreference = .sound(newValue)
                            paywallTrigger = .sound(newValue)
                        } else {
                            store.preferences.selectSound(newValue)
                        }
                    }
                )
            ) {
                ForEach(SoundID.allCases) { sound in
                    Text(sound.isPro && !store.isPro ? "\(sound.displayName)（隠者）" : sound.displayName)
                        .tag(sound)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("表示名プリセット（不在証明用・最大 20 文字）")
                    .font(KumogakureTypography.caption)
                    .foregroundStyle(KumogakureColors.usuzumiText)
                TextField(
                    "表示名（省略可）",
                    text: Binding(
                        get: { store.preferences.displayName },
                        set: { newValue in
                            store.preferences.displayName = TextInputLimiter.clampedGraphemes(
                                newValue,
                                limit: AppConfig.maxDisplayNameLength
                            )
                        }
                    )
                )
                .foregroundStyle(KumogakureColors.washiText)
            }

            Toggle(
                "画面を点けたままにする（初期設定）",
                isOn: Binding(
                    get: { store.preferences.keepScreenOn },
                    set: { store.preferences.keepScreenOn = $0 }
                )
            )
            .tint(KumogakureColors.shinonomeAccent)
        }
    }

    private var notificationsSection: some View {
        Section("通知") {
            HStack {
                Text("通知の許可状態")
                Spacer()
                Text(notificationStatusLabel)
                    .foregroundStyle(notificationStatusColor)
            }

            if notificationStatus == .notDetermined {
                Button("通知を許可する") {
                    Task {
                        _ = await store.requestNotificationAuthorization()
                        notificationStatus = await store.notificationAuthorizationStatus()
                    }
                }
                .foregroundStyle(KumogakureColors.shinonomeAccent)
            } else if notificationStatus == .denied {
                Button("設定アプリを開く") {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }
                .foregroundStyle(KumogakureColors.shinonomeAccent)
            }
        }
    }

    private var supportAndLegalSection: some View {
        Section("サポート・法務") {
            Button("利用規約") {
                safariDestination = SafariDestination(url: AppConfig.termsOfServiceURL)
            }
            .foregroundStyle(KumogakureColors.washiText)

            Button("プライバシーポリシー") {
                safariDestination = SafariDestination(url: AppConfig.privacyPolicyURL)
            }
            .foregroundStyle(KumogakureColors.washiText)

            Button("お問い合わせ・不具合報告") {
                safariDestination = SafariDestination(url: AppConfig.contactFormURL)
            }
            .foregroundStyle(KumogakureColors.washiText)

            HStack {
                Text("アプリバージョン")
                Spacer()
                Text(appVersionText)
                    .foregroundStyle(KumogakureColors.usuzumiText)
            }

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = store.anonymousUserUUID
                #endif
                copiedSupportID = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copiedSupportID ? "匿名サポート ID をコピーしました" : "匿名サポート ID をコピー")
                        .foregroundStyle(KumogakureColors.washiText)
                    Text(store.anonymousUserUUID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
        }
    }

    // MARK: - Helpers

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized: return "許可済み"
        case .provisional: return "仮許可"
        case .ephemeral: return "一時許可"
        case .denied: return "オフ（設定で変更可）"
        case .notDetermined: return "未設定"
        @unknown default: return "未設定"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return KumogakureColors.asagiInfo
        case .denied:
            return KumogakureColors.shuinAccent
        case .notDetermined:
            return KumogakureColors.usuzumiText
        @unknown default:
            return KumogakureColors.usuzumiText
        }
    }

    @MainActor
    private func openManageSubscriptions() async {
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            return
        }
        try? await AppStore.showManageSubscriptions(in: windowScene)
        await store.subscriptionManager.refreshEntitlement()
        #endif
    }

    private func applyPendingProPreference() {
        guard store.isPro, let pending = pendingProPreference else {
            pendingProPreference = nil
            return
        }
        pendingProPreference = nil
        switch pending {
        case .theme(let theme):
            store.preferences.selectTheme(theme)
        case .sound(let sound):
            store.preferences.selectSound(sound)
        case .purposeCustom:
            store.preferences.selectPurpose(.custom)
        }
    }
}
