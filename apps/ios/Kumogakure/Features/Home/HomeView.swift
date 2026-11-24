import SwiftUI

/// S-01 Home Screen: 3-second start without login, preset durations, purpose, landscape, and sound.
struct HomeView: View {
    @Bindable var store: DetoxSessionStore

    @State private var showCustomDurationPicker = false
    @State private var showHistorySheet = false
    @State private var showSettingsSheet = false
    @State private var paywallTriggerReason: String?
    @State private var selectionFeedbackCount = 0
    @State private var nowForReturnPreview = Date()

    private var preferences: UserPreferencesStore {
        store.preferences
    }

    private var activeTheme: ThemeID {
        ThemeID.resolved(rawValue: preferences.themeIDRaw, isPro: store.isPro)
    }

    private var activeSound: SoundID {
        SoundID.resolved(rawValue: preferences.soundIDRaw, isPro: store.isPro)
    }

    private var activePurpose: PurposeID {
        PurposeID.resolved(rawValue: preferences.purposeIDRaw, isPro: store.isPro)
    }

    private var morningPreview: MorningTargetResult {
        MorningTargetCalculator.calculate(
            now: nowForReturnPreview,
            morningTargetMinutes: preferences.morningTargetMinutes
        )
    }

    private var returnEstimateLabel: String {
        if preferences.selectedDurationIsMorning {
            let target = DurationFormatter.morningTargetString(
                minutesSinceMidnight: preferences.morningTargetMinutes
            )
            return "\(morningPreview.returnSummary())（目標 \(target)）"
        }
        let endDate = nowForReturnPreview.addingTimeInterval(TimeInterval(preferences.durationMinutes * 60))
        let timeString = DurationFormatter.clockTimeString(endDate)
        return "約 \(DurationFormatter.japaneseDuration(minutes: preferences.durationMinutes))（\(timeString) 頃帰還）"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FogView(theme: activeTheme, progress: 0.22, isPaused: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    durationSection
                    purposeSection
                    themeSection
                    soundSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 168)
            }
            .scrollIndicators(.hidden)

            bottomCtaOverlay
        }
        .sensoryFeedback(.selection, trigger: selectionFeedbackCount)
        .onAppear {
            nowForReturnPreview = Date()
        }
        .onDisappear {
            store.stopSoundPreview()
        }
        .sheet(isPresented: $showCustomDurationPicker) {
            CustomDurationPickerSheet(
                selectedMinutes: Binding(
                    get: { preferences.durationMinutes },
                    set: { preferences.durationMinutes = $0 }
                )
            ) { chosen in
                preferences.selectPresetDuration(minutes: chosen)
                selectionFeedbackCount += 1
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            Week4HistoryPlaceholderSheet(
                store: store,
                onOpenPaywall: { reason in
                    showHistorySheet = false
                    paywallTriggerReason = reason
                }
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            Week4SettingsPlaceholderSheet(
                store: store,
                onOpenPaywall: { reason in
                    showSettingsSheet = false
                    paywallTriggerReason = reason
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { paywallTriggerReason != nil },
                set: { if !$0 { paywallTriggerReason = nil } }
            )
        ) {
            Week4PaywallPlaceholderSheet(
                reason: paywallTriggerReason ?? "隠者プランのご案内"
            )
        }
        .sheet(
            isPresented: Binding(
                get: { store.state == .preparingShare },
                set: { if !$0 && store.state == .preparingShare { store.cancelSharePreparation() } }
            )
        ) {
            Week4SharePlaceholderSheet(store: store)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("雲隠れ")
                    .font(KumogakureTypography.appTitle)
                    .foregroundStyle(KumogakureColors.washiText)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Image(systemName: "book.closed")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(KumogakureColors.washiText)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(KumogakureColors.yonagaSurface.opacity(0.8)))
                            .overlay(Circle().stroke(KumogakureColors.mistBorder, lineWidth: 1))
                    }
                    .accessibilityLabel("雲隠れ帳を開く")
                    .accessibilityHint("これまでの休息記録を確認します")

                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(KumogakureColors.washiText)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(KumogakureColors.yonagaSurface.opacity(0.8)))
                            .overlay(Circle().stroke(KumogakureColors.mistBorder, lineWidth: 1))
                    }
                    .accessibilityLabel("設定を開く")
                    .accessibilityHint("朝の目標時刻やアプリ設定を変更します")
                }
            }

            QuietStatusBadge(
                othersCount: store.othersActiveCount,
                zeroCopy: "いま、穏やかな静寂が広がっています"
            )
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("雲隠れの時間")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(DurationPreset.standardOptions) { preset in
                    let isSelected = isPresetSelected(preset)
                    KumogakureChip(
                        title: chipTitle(for: preset),
                        isSelected: isSelected
                    ) {
                        handleDurationTap(preset)
                    }
                }
            }

            Text(returnEstimateLabel)
                .font(KumogakureTypography.caption)
                .foregroundStyle(KumogakureColors.usuzumiText)
                .padding(.top, 2)
        }
    }

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("過ごし方")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PurposeID.allCases) { purpose in
                        let isSelected = (activePurpose == purpose)
                        KumogakureChip(
                            title: purpose.displayName,
                            isSelected: isSelected,
                            showProBadge: purpose.isPro && !store.isPro
                        ) {
                            handlePurposeTap(purpose)
                        }
                    }
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("風景")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ThemeID.allCases) { theme in
                        themeCard(theme)
                    }
                }
            }
        }
    }

    private func themeCard(_ theme: ThemeID) -> some View {
        let isSelected = (activeTheme == theme)
        let isLocked = theme.isPro && !store.isPro

        return Button {
            if isLocked {
                paywallTriggerReason = "「\(theme.displayName)」は隠者プランで解放されます"
            } else {
                preferences.selectTheme(theme)
                selectionFeedbackCount += 1
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(theme.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 132, height: 84)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(KumogakureColors.sumiBg.opacity(isLocked ? 0.35 : 0.12))
                        )

                    if isLocked {
                        ProBadge()
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(KumogakureTypography.chipLabel)
                        .foregroundStyle(KumogakureColors.washiText)
                    Text(theme.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(KumogakureColors.usuzumiText)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: 152, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(KumogakureColors.yonagaSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName)\(isLocked ? "、隠者プラン限定" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("環境音")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SoundID.allCases) { sound in
                        soundCard(sound)
                    }
                }
            }
        }
    }

    private func soundCard(_ sound: SoundID) -> some View {
        let isSelected = (activeSound == sound)
        let isLocked = sound.isPro && !store.isPro

        return Button {
            if isLocked {
                paywallTriggerReason = "環境音「\(sound.displayName)」は隠者プランで解放されます"
            } else {
                preferences.selectSound(sound)
                selectionFeedbackCount += 1
                store.previewSound(sound)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: sound.sfSymbol)
                        .font(.system(size: 18))
                        .foregroundStyle(
                            isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.washiText
                        )
                    Spacer()
                    if isLocked {
                        ProBadge()
                    }
                }

                Text(sound.displayName)
                    .font(KumogakureTypography.chipLabel)
                    .foregroundStyle(KumogakureColors.washiText)
            }
            .padding(12)
            .frame(width: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(KumogakureColors.yonagaSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("環境音 \(sound.displayName)\(isLocked ? "、隠者プラン限定" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bottomCtaOverlay: some View {
        VStack(spacing: 8) {
            Button("不在証明を作って雲隠れ") {
                store.openSharePreparation()
            }
            .buttonStyle(KumogakurePrimaryButtonStyle())

            Button("シェアせず静かに始める") {
                Task {
                    await store.beginQuietSessionWithNotificationPrompt()
                }
            }
            .buttonStyle(KumogakureSecondaryButtonStyle())
            .accessibilityHint("不在証明を発行せず、すぐさま雲隠れを開始します")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                stops: [
                    .init(color: KumogakureColors.sumiBg.opacity(0.0), location: 0.0),
                    .init(color: KumogakureColors.sumiBg.opacity(0.88), location: 0.25),
                    .init(color: KumogakureColors.sumiBg.opacity(0.98), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers

    private func isPresetSelected(_ preset: DurationPreset) -> Bool {
        preferences.activeDurationPreset == preset
    }

    private func chipTitle(for preset: DurationPreset) -> String {
        if case .custom = preset, preferences.activeDurationPreset == .custom {
            return DurationFormatter.japaneseDuration(minutes: preferences.durationMinutes)
        }
        return preset.chipTitle
    }

    private func handleDurationTap(_ preset: DurationPreset) {
        nowForReturnPreview = Date()
        switch preset {
        case .minutes(let value):
            preferences.selectPresetDuration(minutes: value)
            selectionFeedbackCount += 1
        case .untilMorning:
            preferences.selectUntilMorning()
            selectionFeedbackCount += 1
        case .custom:
            showCustomDurationPicker = true
        }
    }

    private func handlePurposeTap(_ purpose: PurposeID) {
        if purpose.isPro && !store.isPro {
            paywallTriggerReason = "自由な一言入力は隠者プランで解放されます"
        } else {
            preferences.selectPurpose(purpose)
            selectionFeedbackCount += 1
        }
    }
}
