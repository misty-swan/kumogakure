import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Minimal Week 3 bridge sheets for S-02 / S-06 / S-07 / S-08 (expanded in Week 4).
struct Week4SharePlaceholderSheet: View {
    @Bindable var store: DetoxSessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    KumogakureCardContainer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("不在証明の発行・カード共有（Week 4 実装）")
                                .font(KumogakureTypography.sectionHeading)
                                .foregroundStyle(KumogakureColors.washiText)
                            Text("URL 発行と 1:1 / 9:16 画像カード生成は Week 4 で連携します。いまはそのまま雲隠れを開始できます。")
                                .font(KumogakureTypography.caption)
                                .foregroundStyle(KumogakureColors.usuzumiText)
                        }
                    }

                    Spacer()

                    Button("共有をスキップして始める") {
                        Task {
                            await store.startSessionFromShareSheet(
                                durationMinutes: store.resolvedSelectedDurationMinutes(),
                                isPublic: false
                            )
                        }
                    }
                    .buttonStyle(KumogakurePrimaryButtonStyle())

                    Button("ホームへ戻る") {
                        store.cancelSharePreparation()
                        dismiss()
                    }
                    .buttonStyle(KumogakureSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("不在証明の準備")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        store.cancelSharePreparation()
                        dismiss()
                    }
                    .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
        }
    }
}

struct Week4HistoryPlaceholderSheet: View {
    @Bindable var store: DetoxSessionStore
    let onOpenPaywall: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var recentRecords: [DetoxSessionRecord] {
        store.fetchRecentHistoryRecords()
    }

    private var lockedCount: Int {
        store.countLockedHistoryRecords()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        KumogakureCardContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("累計雲隠れ時間")
                                        .font(KumogakureTypography.caption)
                                        .foregroundStyle(KumogakureColors.usuzumiText)
                                    Text(DurationFormatter.japaneseDuration(
                                        seconds: store.cumulativeSummary.totalCompletedSeconds
                                    ))
                                    .font(KumogakureTypography.sectionHeading)
                                    .foregroundStyle(KumogakureColors.washiText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("完遂回数")
                                        .font(KumogakureTypography.caption)
                                        .foregroundStyle(KumogakureColors.usuzumiText)
                                    Text("\(store.cumulativeSummary.completedCount) 回")
                                        .font(KumogakureTypography.sectionHeading)
                                        .foregroundStyle(KumogakureColors.shinonomeAccent)
                                }
                            }
                        }

                        if recentRecords.isEmpty {
                            KumogakureCardContainer {
                                Text("まだ雲隠れの記録はありません。最初の静寂を始めてみましょう。")
                                    .font(KumogakureTypography.subheadline)
                                    .foregroundStyle(KumogakureColors.usuzumiText)
                            }
                        } else {
                            ForEach(recentRecords, id: \.localID) { record in
                                KumogakureCardContainer {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(ThemeID(rawValue: record.themeID)?.displayName ?? "霧の山並み")
                                                .font(KumogakureTypography.chipLabel)
                                                .foregroundStyle(KumogakureColors.washiText)
                                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(KumogakureTypography.caption)
                                                .foregroundStyle(KumogakureColors.usuzumiText)
                                        }
                                        Spacer()
                                        Text(statusLabel(for: record.status))
                                            .font(KumogakureTypography.caption)
                                            .foregroundStyle(KumogakureColors.shinonomeAccent)
                                    }
                                }
                            }
                        }

                        if lockedCount > 0 {
                            Button {
                                onOpenPaywall("これより先の雲隠れ帳は「隠者プラン」で開けます")
                            } label: {
                                KumogakureCardContainer {
                                    HStack {
                                        Text("これまでの記録（\(lockedCount) 件）は隠者プランで閲覧できます")
                                            .font(KumogakureTypography.caption)
                                            .foregroundStyle(KumogakureColors.usuzumiText)
                                        Spacer()
                                        ProBadge()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("雲隠れ帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(KumogakureColors.shinonomeAccent)
                }
            }
        }
    }

    private func statusLabel(for status: SessionStatus) -> String {
        switch status {
        case .completed: return "完遂"
        case .canceled: return "途中帰還"
        case .interrupted: return "離脱"
        case .active, .gracePeriod: return "進行中"
        }
    }
}

struct Week4SettingsPlaceholderSheet: View {
    @Bindable var store: DetoxSessionStore
    let onOpenPaywall: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copiedSupportID = false

    private var morningOptions: [Int] {
        stride(
            from: AppConfig.minMorningTargetMinutes,
            through: AppConfig.maxMorningTargetMinutes,
            by: AppConfig.morningTargetStepMinutes
        ).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("プラン") {
                    Button {
                        onOpenPaywall("隠者プラン（Pro）のご案内")
                    } label: {
                        HStack {
                            Text("現在のプラン")
                            Spacer()
                            Text(store.isPro ? "隠者（Pro）" : "旅人（無料）")
                                .foregroundStyle(KumogakureColors.shinonomeAccent)
                        }
                    }
                }

                Section("「明日の朝まで」の目標時刻") {
                    Picker(
                        "朝の目標時刻",
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
                }

                Section("サポート") {
                    Link("お問い合わせ・不具合報告", destination: AppConfig.contactFormURL)
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = store.anonymousUserUUID
                        #endif
                        copiedSupportID = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copiedSupportID ? "匿名サポート ID をコピーしました" : "匿名サポート ID をコピー")
                            Text(store.anonymousUserUUID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(KumogakureColors.usuzumiText)
                        }
                    }
                }
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
        }
    }
}

struct Week4PaywallPlaceholderSheet: View {
    let reason: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        ProBadge()
                        Text("隠者プラン（Pro）")
                            .font(KumogakureTypography.appTitle)
                            .foregroundStyle(KumogakureColors.washiText)
                    }

                    Text(reason)
                        .font(KumogakureTypography.body)
                        .foregroundStyle(KumogakureColors.usuzumiText)

                    KumogakureCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("・すべての風景・環境音を解放")
                            Text("・不在証明の透かし非表示・限定デザイン・自由な一言")
                            Text("・全期間の「雲隠れ帳」履歴と統計グラフ")
                            Text("・年額 ¥2,400（7 日間無料トライアル付）／ 月額 ¥300")
                        }
                        .font(KumogakureTypography.subheadline)
                        .foregroundStyle(KumogakureColors.washiText)
                    }

                    Text("ローカル StoreKit 課金連携は Week 4 で有効化されます。")
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.usuzumiText)

                    Spacer()

                    Button("閉じる") {
                        dismiss()
                    }
                    .buttonStyle(KumogakurePrimaryButtonStyle(isEmphasized: false))
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
        }
    }
}
