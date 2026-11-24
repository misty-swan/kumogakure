import Charts
import SwiftUI

/// S-06 Kumogakure History & Analytics Screen (`ux-and-screens.md` S-06).
struct HistoryView: View {
    private enum AnalyticsTab: String, CaseIterable, Identifiable {
        case weekday = "曜日別"
        case timeBand = "時間帯別"

        var id: String { rawValue }
    }

    @Bindable var store: DetoxSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AnalyticsTab = .weekday
    @State private var paywallTrigger: PaywallTrigger?

    private var visibleRecords: [DetoxSessionRecord] {
        store.fetchRecentHistoryRecords()
    }

    private var lockedCount: Int {
        store.countLockedHistoryRecords()
    }

    private var analytics: HistoryAnalyticsSummary {
        HistoryAnalytics.summarize(records: visibleRecords)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryHeaderCard
                        analyticsSection
                        recordsSection
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("雲隠れ帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(KumogakureColors.shinonomeAccent)
                }
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(store: store, trigger: trigger)
            }
        }
    }

    // MARK: - Sections

    private var summaryHeaderCard: some View {
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
    }

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("休息の傾向")
                    .font(KumogakureTypography.sectionHeading)
                    .foregroundStyle(KumogakureColors.washiText)
                if !store.isPro {
                    ProBadge()
                }
                Spacer()
            }

            if store.isPro {
                KumogakureCardContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("集計軸", selection: $selectedTab) {
                            ForEach(AnalyticsTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)

                        if analytics.totalCompletedCount == 0 {
                            Text("完遂したセッションが増えると、曜日・時間帯別の分布がここに描かれます。")
                                .font(KumogakureTypography.caption)
                                .foregroundStyle(KumogakureColors.usuzumiText)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            chartBody(summary: analytics)
                                .frame(height: 170)
                        }
                    }
                }
            } else {
                Button {
                    paywallTrigger = .historyAnalytics
                } label: {
                    ZStack {
                        KumogakureCardContainer {
                            chartBody(summary: Self.previewAnalytics)
                                .frame(height: 150)
                                .blur(radius: 6)
                                .opacity(0.55)
                        }

                        VStack(spacing: 8) {
                            ProBadge()
                            Text("曜日別・時間帯別の統計グラフは隠者プランで解放")
                                .font(KumogakureTypography.caption.weight(.medium))
                                .foregroundStyle(KumogakureColors.washiText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func chartBody(summary: HistoryAnalyticsSummary) -> some View {
        switch selectedTab {
        case .weekday:
            Chart(summary.weekdayStats) { stat in
                BarMark(
                    x: .value("曜日", stat.label),
                    y: .value("時間（分）", stat.totalMinutes)
                )
                .foregroundStyle(KumogakureColors.shinonomeAccent.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(KumogakureColors.mistBorder)
                    AxisValueLabel()
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }

        case .timeBand:
            Chart(summary.timeBandStats) { stat in
                BarMark(
                    x: .value("時間帯", stat.band.label),
                    y: .value("時間（分）", stat.totalMinutes)
                )
                .foregroundStyle(KumogakureColors.asagiInfo.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(KumogakureColors.mistBorder)
                    AxisValueLabel()
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("雲隠れの記録")
                    .font(KumogakureTypography.sectionHeading)
                    .foregroundStyle(KumogakureColors.washiText)
                Spacer()
                if !store.isPro {
                    Text("直近 7 日間")
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }

            if visibleRecords.isEmpty && lockedCount == 0 {
                KumogakureCardContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("まだ雲隠れの記録はありません。最初の静寂を始めてみましょう。")
                            .font(KumogakureTypography.subheadline)
                            .foregroundStyle(KumogakureColors.usuzumiText)

                        Button("始める") {
                            dismiss()
                        }
                        .buttonStyle(KumogakurePrimaryButtonStyle())
                    }
                }
            } else {
                ForEach(visibleRecords, id: \.localID) { record in
                    historyRow(for: record)
                }

                if lockedCount > 0 {
                    Button {
                        paywallTrigger = .historyLocked
                    } label: {
                        KumogakureCardContainer {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("これより先の雲隠れ帳は「隠者プラン」で開けます")
                                        .font(KumogakureTypography.chipLabel)
                                        .foregroundStyle(KumogakureColors.washiText)
                                    Spacer()
                                    ProBadge()
                                }
                                Text("これまでの記録（\(lockedCount) 件）は隠者プランで閲覧できます")
                                    .font(KumogakureTypography.caption)
                                    .foregroundStyle(KumogakureColors.usuzumiText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyRow(for record: DetoxSessionRecord) -> some View {
        let theme = ThemeID(rawValue: record.themeID) ?? .mistyMountain
        let purpose = PurposeID(rawValue: record.purposeID) ?? .rest

        return KumogakureCardContainer {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(theme.displayName)
                            .font(KumogakureTypography.chipLabel)
                            .foregroundStyle(KumogakureColors.washiText)

                        Text(purpose.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(KumogakureColors.usuzumiText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(KumogakureColors.sumiBg.opacity(0.6)))
                    }

                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(DurationFormatter.japaneseDuration(seconds: record.actualDurationSeconds))
                        .font(KumogakureTypography.subheadline.weight(.medium))
                        .foregroundStyle(KumogakureColors.washiText)

                    Text(statusLabel(for: record.status))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor(for: record.status))
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

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .completed: return KumogakureColors.shinonomeAccent
        case .canceled: return KumogakureColors.usuzumiText
        case .interrupted: return KumogakureColors.shuinAccent
        case .active, .gracePeriod: return KumogakureColors.asagiInfo
        }
    }

    private static let previewAnalytics = HistoryAnalyticsSummary(
        weekdayStats: [
            WeekdayStat(id: 2, label: "月", totalMinutes: 45, sessionCount: 1),
            WeekdayStat(id: 3, label: "火", totalMinutes: 30, sessionCount: 1),
            WeekdayStat(id: 4, label: "水", totalMinutes: 90, sessionCount: 2),
            WeekdayStat(id: 5, label: "木", totalMinutes: 60, sessionCount: 1),
            WeekdayStat(id: 6, label: "金", totalMinutes: 120, sessionCount: 2),
            WeekdayStat(id: 7, label: "土", totalMinutes: 180, sessionCount: 3),
            WeekdayStat(id: 1, label: "日", totalMinutes: 75, sessionCount: 2),
        ],
        timeBandStats: [
            TimeBandStat(band: .earlyMorning, totalMinutes: 30, sessionCount: 1),
            TimeBandStat(band: .daytime, totalMinutes: 60, sessionCount: 1),
            TimeBandStat(band: .evening, totalMinutes: 180, sessionCount: 3),
            TimeBandStat(band: .lateNight, totalMinutes: 240, sessionCount: 3),
        ],
        totalCompletedCount: 12,
        totalCompletedMinutes: 600
    )
}
