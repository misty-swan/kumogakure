import SwiftUI

/// S-05 Early Return / Interruption Screen: non-judgmental tone encouraging a calm retry.
struct EarlyReturnView: View {
    @Bindable var store: DetoxSessionStore
    let summary: SessionResultSummary

    @State private var appeared = false

    private var isInterrupted: Bool {
        summary.status == .interrupted
    }

    private var elapsedMinutes: Int {
        max(0, summary.actualDurationSeconds / 60)
    }

    private var headingText: String {
        isInterrupted ? "霧が深くなりました" : "雲の中から戻りました"
    }

    private var bodyText: String {
        if isInterrupted {
            return "ほかの画面へ移ったため、今回の雲隠れはここまでとなりました。深呼吸して、またいつでも始められます。"
        }
        if elapsedMinutes > 0 {
            return "今回は \(elapsedMinutes) 分、静かな時間を過ごしました。また一息つきたくなったらお越しください。"
        }
        return "また一息つきたくなったらお越しください。"
    }

    var body: some View {
        ZStack {
            FogView(theme: summary.theme, progress: 0.04, isPaused: false)

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 14) {
                    Text(headingText)
                        .font(KumogakureTypography.heroTitle)
                        .foregroundStyle(KumogakureColors.washiText)

                    Text(bodyText)
                        .font(KumogakureTypography.body)
                        .foregroundStyle(KumogakureColors.usuzumiText)
                        .lineSpacing(5)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

                Spacer()

                VStack(spacing: 12) {
                    Button("もう一度雲隠れする") {
                        store.retryWithLastSettings()
                    }
                    .buttonStyle(KumogakurePrimaryButtonStyle())

                    Button("ホームへ戻る") {
                        store.returnToHome()
                    }
                    .buttonStyle(KumogakureSecondaryButtonStyle())
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .sensoryFeedback(.warning, trigger: appeared)
        .onAppear {
            appeared = true
        }
    }
}
