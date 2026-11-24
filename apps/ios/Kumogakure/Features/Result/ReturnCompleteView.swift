import SwiftUI

/// S-04 Return Complete Screen: clear landscape, gentle praise, cumulative totals, and post-session share.
struct ReturnCompleteView: View {
    @Bindable var store: DetoxSessionStore
    let summary: SessionResultSummary

    @State private var appeared = false
    @State private var showPaywallPlaceholder = false

    private var sessionDurationText: String {
        DurationFormatter.japaneseDuration(seconds: summary.actualDurationSeconds)
    }

    private var cumulativeDurationText: String {
        DurationFormatter.japaneseDuration(seconds: store.cumulativeSummary.totalCompletedSeconds)
    }

    private var completionShareText: String {
        "\(sessionDurationText)の雲隠れから帰還しました。静かな時間でした。\n#雲隠れ"
    }

    var body: some View {
        ZStack {
            FogView(theme: summary.theme, progress: 1.0, isPaused: true)

            RadialGradient(
                colors: [
                    KumogakureColors.shinonomeAccent.opacity(0.18),
                    Color.clear,
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 12) {
                    Text("おかえりなさい。")
                        .font(KumogakureTypography.heroTitle)
                        .foregroundStyle(KumogakureColors.washiText)

                    Text("\(sessionDurationText) の静寂を得ました。")
                        .font(KumogakureTypography.body)
                        .foregroundStyle(KumogakureColors.washiText.opacity(0.92))
                }
                .multilineTextAlignment(.center)

                KumogakureCardContainer {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("累計雲隠れ時間")
                                .font(KumogakureTypography.caption)
                                .foregroundStyle(KumogakureColors.usuzumiText)
                            Text(cumulativeDurationText)
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

                if store.shouldShowMilestoneProBanner {
                    milestoneProBanner
                }

                Spacer()

                VStack(spacing: 12) {
                    ShareLink(item: completionShareText) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("今日の雲隠れを記録でシェア")
                        }
                        .font(KumogakureTypography.chipLabel)
                        .foregroundStyle(KumogakureColors.washiText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(KumogakureColors.yonagaSurface.opacity(0.88))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(KumogakureColors.mistBorder, lineWidth: 1)
                        )
                    }

                    Button("ホームへ戻る") {
                        store.returnToHome()
                    }
                    .buttonStyle(KumogakurePrimaryButtonStyle())
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            appeared = true
        }
        .sheet(isPresented: $showPaywallPlaceholder) {
            Week4PaywallPlaceholderSheet(reason: "すべての風景・環境音と雲隠れ帳の全履歴を解放できます")
        }
    }

    private var milestoneProBanner: some View {
        KumogakureCardContainer {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProBadge()
                        Text("静かな節目に")
                            .font(KumogakureTypography.chipLabel)
                            .foregroundStyle(KumogakureColors.washiText)
                    }
                    Text("月夜の湖畔や焚き火の音など、さらに深い静寂を隠者プランでご用意しています。")
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.usuzumiText)
                    Button("詳しく見る") {
                        showPaywallPlaceholder = true
                    }
                    .font(KumogakureTypography.caption.weight(.semibold))
                    .foregroundStyle(KumogakureColors.shinonomeAccent)
                    .padding(.top, 2)
                }

                Spacer()

                Button {
                    store.dismissProMilestoneBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .foregroundStyle(KumogakureColors.usuzumiText)
                        .padding(6)
                }
                .accessibilityLabel("案内を閉じる")
            }
        }
    }
}
