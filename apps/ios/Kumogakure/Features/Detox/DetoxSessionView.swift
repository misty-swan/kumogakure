import SwiftUI

/// S-03 Active Detox Screen: clearing fog layers, absolute countdown, sound mute, keep-screen-on, and early return.
struct DetoxSessionView: View {
    @Bindable var store: DetoxSessionStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var showCancelDialog = false
    @State private var areControlsHighlighted = true
    @State private var controlInteractionToken = 0
    @State private var startFeedbackTrigger = false

    private var returnTimeText: String {
        guard let endsAt = store.activePlannedEndsAt else { return "" }
        return "\(DurationFormatter.clockTimeString(endsAt)) 帰還予定"
    }

    private var isInGracePeriod: Bool {
        if case .gracePeriod = store.state {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            FogView(
                theme: store.activeTheme,
                progress: store.timerEngine.progress,
                isPaused: scenePhase != .active
            )

            VStack(spacing: 24) {
                topStatusSection
                    .padding(.top, 28)

                Spacer()

                centerTimerSection

                Spacer()

                bottomControlsSection
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            registerControlInteraction()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: startFeedbackTrigger)
        .onAppear {
            startFeedbackTrigger.toggle()
            registerControlInteraction()
        }
        .task(id: controlInteractionToken) {
            try? await Task.sleep(
                nanoseconds: UInt64(AppConfig.controlsAutoDimDelaySeconds * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) {
                areControlsHighlighted = false
            }
        }
        .confirmationDialog(
            "霧が晴れる前に戻りますか？",
            isPresented: $showCancelDialog,
            titleVisibility: .visible
        ) {
            Button("戻る（途中帰還）", role: .destructive) {
                store.confirmEarlyCancel()
            }
            Button("雲隠れを続ける", role: .cancel) {}
        } message: {
            Text("いままでの静かな時間は記録に残ります。")
        }
    }

    // MARK: - Sections

    private var topStatusSection: some View {
        VStack(spacing: 10) {
            Text(isInGracePeriod ? "霧が濃くなり始めています" : "ただいま雲隠れ中")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            if !returnTimeText.isEmpty {
                Text(returnTimeText)
                    .font(KumogakureTypography.subheadline)
                    .foregroundStyle(KumogakureColors.usuzumiText)
            }

            QuietStatusBadge(
                othersCount: store.othersActiveCount,
                zeroCopy: "いま、深い静寂が広がっています"
            )
            .padding(.top, 4)
        }
    }

    private var centerTimerSection: some View {
        VStack(spacing: 18) {
            Text(DurationFormatter.countdownString(remainingSeconds: store.timerEngine.remainingSeconds))
                .font(KumogakureTypography.timerDisplay)
                .foregroundStyle(KumogakureColors.washiText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityLabel(
                    DurationFormatter.accessibilityRemainingText(
                        remainingSeconds: store.timerEngine.remainingSeconds
                    )
                )

            // Subtle horizontal ink progress line.
            GeometryReader { geometry in
                let width = geometry.size.width
                let clampedProgress = min(1.0, max(0.0, store.timerEngine.progress))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(KumogakureColors.mistBorder.opacity(0.65))
                        .frame(height: 2)
                    Capsule()
                        .fill(KumogakureColors.shinonomeAccent.opacity(0.9))
                        .frame(width: max(4, width * clampedProgress), height: 2)
                }
            }
            .frame(maxWidth: 220, maxHeight: 4)
            .accessibilityHidden(true)
        }
    }

    private var bottomControlsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                if store.activeSound != .none {
                    Button {
                        registerControlInteraction()
                        store.toggleAudioMute()
                    } label: {
                        Label(
                            store.isAudioMuted ? "消音中" : store.activeSound.displayName,
                            systemImage: store.isAudioMuted ? "speaker.slash" : "speaker.wave.2"
                        )
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.washiText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(KumogakureColors.yonagaSurface.opacity(0.75))
                        )
                        .overlay(
                            Capsule()
                                .stroke(KumogakureColors.mistBorder, lineWidth: 1)
                        )
                    }
                    .accessibilityLabel(store.isAudioMuted ? "環境音を再開" : "環境音を消音")
                    .accessibilityHint("タップして環境音の再生と消音を切り替えます")
                }

                Button {
                    registerControlInteraction()
                    store.toggleKeepScreenOn()
                } label: {
                    Label(
                        "画面を点けたまま",
                        systemImage: store.preferences.keepScreenOn ? "sun.max.fill" : "moon.zzz"
                    )
                    .font(KumogakureTypography.caption)
                    .foregroundStyle(
                        store.preferences.keepScreenOn
                            ? KumogakureColors.shinonomeAccent
                            : KumogakureColors.washiText
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(KumogakureColors.yonagaSurface.opacity(0.75))
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                store.preferences.keepScreenOn
                                    ? KumogakureColors.shinonomeAccent
                                    : KumogakureColors.mistBorder,
                                lineWidth: 1
                            )
                    )
                }
                .accessibilityLabel("画面を点けたままにする")
                .accessibilityValue(store.preferences.keepScreenOn ? "オン" : "オフ")
                .accessibilityHint("スリープを抑止して霧が晴れる様子を見守ります")
            }

            Button("途中帰還する") {
                registerControlInteraction()
                showCancelDialog = true
            }
            .buttonStyle(KumogakureSecondaryButtonStyle())
            .accessibilityHint("確認のうえ、今回の雲隠れを終了します")
        }
        .opacity(areControlsHighlighted ? 1.0 : 0.30)
    }

    private func registerControlInteraction() {
        withAnimation(.easeIn(duration: 0.2)) {
            areControlsHighlighted = true
        }
        controlInteractionToken += 1
    }
}
