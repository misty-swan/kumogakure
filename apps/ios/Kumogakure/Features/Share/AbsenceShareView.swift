import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// S-02 Declaration & Share Sheet Screen (`ux-and-screens.md` S-02).
struct AbsenceShareView: View {
    private enum PostPurchaseAction {
        case selectPurposeCustom
        case selectCardStyle(CardStyle)
        case enableHideWatermark
    }

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let items: [Any]
        let remoteSession: CreateSessionResponse?
        let isPublic: Bool
    }

    @Bindable var store: DetoxSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var selectedPurpose: PurposeID = .rest
    @State private var customMessageText: String = ""
    @State private var selectedCardStyle: CardStyle = .washiClassic
    @State private var hideWatermark: Bool = false
    @State private var shareOutputFormat: ShareOutputFormat = .urlWithMessage

    @State private var isSubmitting = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var pendingPostPurchaseAction: PostPurchaseAction?
    @State private var shareSheetPayload: ShareSheetPayload?

    @State private var offlineFallbackMessage: String?
    @State private var errorAlertMessage: String?
    @State private var proRequiredAlert = false
    @State private var didInitializeState = false

    private var resolvedDurationMinutes: Int {
        store.resolvedSelectedDurationMinutes()
    }

    private var previewPlannedEndsAt: Date {
        Date().addingTimeInterval(TimeInterval(resolvedDurationMinutes * 60))
    }

    private var activeTheme: ThemeID {
        ThemeID.resolved(rawValue: store.preferences.themeIDRaw, isPro: store.isPro)
    }

    private var effectiveCardStyle: CardStyle {
        CardStyle.resolved(rawValue: selectedCardStyle.rawValue, isPro: store.isPro)
    }

    private var effectiveHideWatermark: Bool {
        hideWatermark && store.isPro
    }

    private var effectiveDisplayName: String? {
        TextInputLimiter.sanitizedOptional(displayName, limit: AppConfig.maxDisplayNameLength)
    }

    private var effectiveMessage: String? {
        if selectedPurpose == .custom && store.isPro {
            return TextInputLimiter.sanitizedOptional(
                customMessageText,
                limit: AppConfig.maxMessageLength
            )
        }
        return selectedPurpose.presetMessage
    }

    private var isUsingCustomMessage: Bool {
        selectedPurpose == .custom && store.isPro && effectiveMessage != nil
    }

    private var cardPayload: AbsenceCardPayload {
        AbsenceCardPayload(
            theme: activeTheme,
            cardStyle: effectiveCardStyle,
            hideWatermark: effectiveHideWatermark,
            displayName: effectiveDisplayName,
            message: effectiveMessage,
            mode: .activeAbsence(plannedEndsAt: previewPlannedEndsAt, timeZone: .current)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                KumogakureColors.sumiBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        cardPreviewSection
                        shareFormatSection
                        displayNameSection
                        messageSection
                        cardStyleSection
                        watermarkSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 152)
                }
                .scrollIndicators(.hidden)

                bottomActionOverlay
            }
            .navigationTitle("不在証明の作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る") {
                        store.cancelSharePreparation()
                        dismiss()
                    }
                    .foregroundStyle(KumogakureColors.usuzumiText)
                    .disabled(isSubmitting)
                }
            }
            .onAppear {
                guard !didInitializeState else { return }
                didInitializeState = true
                displayName = TextInputLimiter.clampedGraphemes(
                    store.preferences.displayName,
                    limit: AppConfig.maxDisplayNameLength
                )
                selectedPurpose = PurposeID.resolved(
                    rawValue: store.preferences.purposeIDRaw,
                    isPro: store.isPro
                )
                selectedCardStyle = CardStyle.resolved(
                    rawValue: store.preferences.cardStyleRaw,
                    isPro: store.isPro
                )
                hideWatermark = store.preferences.hideWatermark && store.isPro
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(store: store, trigger: trigger) {
                    applyPendingPostPurchaseAction()
                }
            }
            .sheet(item: $shareSheetPayload) { payload in
                ActivityViewControllerWrapper(activityItems: payload.items) { _ in
                    shareSheetPayload = nil
                    Task {
                        await store.startSessionFromShareSheet(
                            durationMinutes: resolvedDurationMinutes,
                            isPublic: payload.isPublic,
                            displayName: effectiveDisplayName,
                            customMessage: effectiveMessage,
                            remoteSession: payload.remoteSession,
                            cardStyle: effectiveCardStyle,
                            hideWatermark: effectiveHideWatermark
                        )
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Web URL を発行できませんでした", isPresented: Binding(
                get: { offlineFallbackMessage != nil },
                set: { if !$0 { offlineFallbackMessage = nil } }
            )) {
                Button("画像カードのみで共有して始める") {
                    offlineFallbackMessage = nil
                    presentOfflineImageShareSheet()
                }
                Button("共有せずそのまま始める") {
                    offlineFallbackMessage = nil
                    Task {
                        await store.startSessionFromShareSheet(
                            durationMinutes: resolvedDurationMinutes,
                            isPublic: false,
                            displayName: effectiveDisplayName,
                            customMessage: effectiveMessage,
                            remoteSession: nil,
                            cardStyle: effectiveCardStyle,
                            hideWatermark: effectiveHideWatermark
                        )
                    }
                }
                Button("キャンセル", role: .cancel) {
                    offlineFallbackMessage = nil
                }
            } message: {
                Text(offlineFallbackMessage ?? "通信が不安定なため不在証明 URL を発行できませんでした。端末内で生成した画像カードのみでも共有できます。")
            }
            .alert("文面をご確認ください", isPresented: Binding(
                get: { errorAlertMessage != nil },
                set: { if !$0 { errorAlertMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) {
                    errorAlertMessage = nil
                }
            } message: {
                Text(errorAlertMessage ?? "")
            }
            .alert("隠者プランの確認", isPresented: $proRequiredAlert) {
                Button("隠者プランを見る") {
                    paywallTrigger = .cardStyle(.sumiNight)
                }
                Button("標準設定へ戻す", role: .cancel) {
                    selectedCardStyle = .washiClassic
                    hideWatermark = false
                    if selectedPurpose == .custom {
                        selectedPurpose = .rest
                    }
                    store.preferences.selectCardStyle(.washiClassic)
                    store.preferences.hideWatermark = false
                }
            } message: {
                Text("Pro 限定のデザインまたはカスタム文言がサーバーで未確認となりました。隠者プランをご確認いただくか、標準設定で作成できます。")
            }
        }
    }

    // MARK: - Sections

    private var cardPreviewSection: some View {
        let cardFormat = shareOutputFormat.cardFormat
        let previewWidth: CGFloat = cardFormat == .story ? 168 : 252
        let previewHeight: CGFloat = cardFormat == .story ? 298 : 252
        let scale = previewWidth / cardFormat.pixelSize.width

        return VStack(spacing: 10) {
            AbsenceCardSnapshotView(payload: cardPayload, format: cardFormat)
                .frame(
                    width: cardFormat.pixelSize.width,
                    height: cardFormat.pixelSize.height
                )
                .scaleEffect(scale)
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(KumogakureColors.mistBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)

            Text("\(DurationFormatter.clockTimeString(previewPlannedEndsAt)) 頃帰還（\(DurationFormatter.japaneseDuration(minutes: resolvedDurationMinutes))）")
                .font(KumogakureTypography.caption)
                .foregroundStyle(KumogakureColors.usuzumiText)
        }
        .frame(maxWidth: .infinity)
    }

    private var shareFormatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("シェア形式")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShareOutputFormat.allCases) { format in
                        KumogakureChip(
                            title: format.title,
                            isSelected: shareOutputFormat == format
                        ) {
                            shareOutputFormat = format
                        }
                    }
                }
            }
        }
    }

    private var displayNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("表示名（任意）")
                    .font(KumogakureTypography.sectionHeading)
                    .foregroundStyle(KumogakureColors.washiText)
                Spacer()
                Text("\(displayName.count)/\(AppConfig.maxDisplayNameLength)")
                    .font(KumogakureTypography.caption.monospacedDigit())
                    .foregroundStyle(KumogakureColors.usuzumiText)
            }

            TextField(
                "表示名（省略可・最大 20 文字）",
                text: Binding(
                    get: { displayName },
                    set: { newValue in
                        let clamped = TextInputLimiter.clampedGraphemes(
                            newValue,
                            limit: AppConfig.maxDisplayNameLength
                        )
                        displayName = clamped
                        store.preferences.displayName = clamped
                    }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(KumogakureColors.washiText)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(KumogakureColors.yonagaSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(KumogakureColors.mistBorder, lineWidth: 1)
            )
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("一言メッセージ")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PurposeID.allCases) { purpose in
                        let isLocked = purpose.isPro && !store.isPro
                        KumogakureChip(
                            title: purpose.displayName,
                            isSelected: selectedPurpose == purpose && !isLocked,
                            showProBadge: isLocked
                        ) {
                            if isLocked {
                                pendingPostPurchaseAction = .selectPurposeCustom
                                paywallTrigger = .purposeCustom
                            } else {
                                selectedPurpose = purpose
                                store.preferences.selectPurpose(purpose)
                            }
                        }
                    }
                }
            }

            if selectedPurpose == .custom && store.isPro {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField(
                        "今の一言を自由に入力（最大 40 文字）",
                        text: Binding(
                            get: { customMessageText },
                            set: { newValue in
                                customMessageText = TextInputLimiter.clampedGraphemes(
                                    newValue,
                                    limit: AppConfig.maxMessageLength
                                )
                            }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...3)
                    .foregroundStyle(KumogakureColors.washiText)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(KumogakureColors.yonagaSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(KumogakureColors.shinonomeAccent.opacity(0.6), lineWidth: 1)
                    )

                    Text("\(customMessageText.count)/\(AppConfig.maxMessageLength)")
                        .font(KumogakureTypography.caption.monospacedDigit())
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }
            } else {
                KumogakureCardContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("「\(selectedPurpose.presetMessage ?? "")」")
                            .font(KumogakureTypography.subheadline)
                            .foregroundStyle(KumogakureColors.washiText)

                        if !store.isPro {
                            Button {
                                pendingPostPurchaseAction = .selectPurposeCustom
                                paywallTrigger = .purposeCustom
                            } label: {
                                HStack(spacing: 6) {
                                    ProBadge()
                                    Text("自由な一言は隠者プランで解放")
                                        .font(KumogakureTypography.caption)
                                        .foregroundStyle(KumogakureColors.shinonomeAccent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var cardStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("カードデザイン")
                .font(KumogakureTypography.sectionHeading)
                .foregroundStyle(KumogakureColors.washiText)

            HStack(spacing: 10) {
                ForEach(CardStyle.allCases) { style in
                    let isLocked = style.isPro && !store.isPro
                    let isSelected = (effectiveCardStyle == style)
                    let palette = AbsenceCardPalette.palette(for: style)

                    Button {
                        if isLocked {
                            pendingPostPurchaseAction = .selectCardStyle(style)
                            paywallTrigger = .cardStyle(style)
                        } else {
                            selectedCardStyle = style
                            store.preferences.selectCardStyle(style)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(palette.background)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(palette.seal, lineWidth: 1.5)
                                )
                            Text(style.displayName)
                                .font(KumogakureTypography.chipLabel)
                                .foregroundStyle(KumogakureColors.washiText)
                            if isLocked {
                                ProBadge()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(KumogakureColors.yonagaSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder,
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var watermarkSection: some View {
        KumogakureCardContainer {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("透かしを非表示にする")
                            .font(KumogakureTypography.chipLabel)
                            .foregroundStyle(KumogakureColors.washiText)
                        if !store.isPro {
                            ProBadge()
                        }
                    }
                    Text("右下・下部の「雲隠れ - Kumogakure」表記を消します")
                        .font(KumogakureTypography.caption)
                        .foregroundStyle(KumogakureColors.usuzumiText)
                }

                Spacer()

                if store.isPro {
                    Toggle(
                        "透かしを非表示にする",
                        isOn: Binding(
                            get: { hideWatermark },
                            set: { newValue in
                                hideWatermark = newValue
                                store.preferences.hideWatermark = newValue
                            }
                        )
                    )
                    .labelsHidden()
                    .tint(KumogakureColors.shinonomeAccent)
                } else {
                    Button {
                        pendingPostPurchaseAction = .enableHideWatermark
                        paywallTrigger = .hideWatermark
                    } label: {
                        Text("解放")
                            .font(KumogakureTypography.caption.weight(.semibold))
                            .foregroundStyle(KumogakureColors.shinonomeAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .stroke(KumogakureColors.shinonomeAccent.opacity(0.6), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var bottomActionOverlay: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await issueAndShareAbsenceProof()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(KumogakureColors.sumiBg)
                    }
                    Text(isSubmitting ? "不在証明を発行しています..." : "不在証明を発行して共有する")
                }
            }
            .buttonStyle(KumogakurePrimaryButtonStyle())
            .disabled(isSubmitting)

            Button("共有をスキップして始める") {
                Task {
                    await store.startSessionFromShareSheet(
                        durationMinutes: resolvedDurationMinutes,
                        isPublic: false,
                        displayName: effectiveDisplayName,
                        customMessage: effectiveMessage,
                        remoteSession: nil,
                        cardStyle: effectiveCardStyle,
                        hideWatermark: effectiveHideWatermark
                    )
                }
            }
            .buttonStyle(KumogakureSecondaryButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                stops: [
                    .init(color: KumogakureColors.sumiBg.opacity(0.0), location: 0.0),
                    .init(color: KumogakureColors.sumiBg.opacity(0.92), location: 0.25),
                    .init(color: KumogakureColors.sumiBg.opacity(0.99), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    @MainActor
    private func issueAndShareAbsenceProof() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await store.createPublicRemoteSession(
                durationMinutes: resolvedDurationMinutes,
                displayName: effectiveDisplayName,
                message: effectiveMessage,
                isCustomMessage: isUsingCustomMessage,
                cardStyle: effectiveCardStyle,
                hideWatermark: effectiveHideWatermark
            )

            let endsAt = Date(timeIntervalSince1970: TimeInterval(response.endsAt))
            let fallbackURL = AppConfig.apiBaseURL
                .appendingPathComponent("s")
                .appendingPathComponent(response.id)
                .absoluteString
            let shareURL = response.shareURL ?? fallbackURL

            var items: [Any] = []
            if shareOutputFormat.includesImage {
                let offlineFriendlyPayload = AbsenceCardPayload(
                    theme: activeTheme,
                    cardStyle: effectiveCardStyle,
                    hideWatermark: effectiveHideWatermark,
                    displayName: effectiveDisplayName,
                    message: effectiveMessage,
                    mode: .activeAbsence(plannedEndsAt: endsAt, timeZone: .current)
                )
                #if canImport(UIKit)
                if let image = ShareCardRenderer.renderImage(
                    payload: offlineFriendlyPayload,
                    format: shareOutputFormat.cardFormat
                ) {
                    items.append(image)
                }
                #endif
                items.append(
                    ShareMessageBuilder.imageShareText(
                        plannedEndsAt: endsAt,
                        timeZone: .current,
                        message: effectiveMessage
                    )
                )
            } else {
                items.append(
                    ShareMessageBuilder.urlShareText(
                        plannedEndsAt: endsAt,
                        timeZone: .current,
                        message: effectiveMessage,
                        shareURL: shareURL
                    )
                )
            }

            shareSheetPayload = ShareSheetPayload(
                items: items,
                remoteSession: response,
                isPublic: true
            )
        } catch let apiError as APIError {
            if apiError.isProRequired {
                proRequiredAlert = true
            } else if apiError.isContentPolicyViolation {
                errorAlertMessage = apiError.localizedDescription
            } else if case .serverError(let status, _, let msg, _) = apiError, status == 422 {
                errorAlertMessage = msg
            } else {
                offlineFallbackMessage = "現在サーバーと通信できないため Web URL を発行できませんでした。端末内で生成した画像カードのみでも共有できます。"
            }
        } catch {
            offlineFallbackMessage = "現在サーバーと通信できないため Web URL を発行できませんでした。端末内で生成した画像カードのみでも共有できます。"
        }
    }

    @MainActor
    private func presentOfflineImageShareSheet() {
        var items: [Any] = []
        #if canImport(UIKit)
        if let image = ShareCardRenderer.renderImage(
            payload: cardPayload,
            format: shareOutputFormat.cardFormat
        ) {
            items.append(image)
        }
        #endif
        items.append(
            ShareMessageBuilder.imageShareText(
                plannedEndsAt: previewPlannedEndsAt,
                timeZone: .current,
                message: effectiveMessage
            )
        )
        shareSheetPayload = ShareSheetPayload(
            items: items,
            remoteSession: nil,
            isPublic: false
        )
    }

    private func applyPendingPostPurchaseAction() {
        guard store.isPro, let action = pendingPostPurchaseAction else {
            pendingPostPurchaseAction = nil
            return
        }
        pendingPostPurchaseAction = nil
        switch action {
        case .selectPurposeCustom:
            selectedPurpose = .custom
            store.preferences.selectPurpose(.custom)
        case .selectCardStyle(let style):
            selectedCardStyle = style
            store.preferences.selectCardStyle(style)
        case .enableHideWatermark:
            hideWatermark = true
            store.preferences.hideWatermark = true
        }
    }
}
