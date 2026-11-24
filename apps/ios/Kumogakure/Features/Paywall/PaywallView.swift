import SwiftUI

/// S-07 Paywall Screen compliant with App Review Guideline 3.1.2 (`monetization.md` §4).
struct PaywallView: View {
    @Bindable var store: DetoxSessionStore
    let trigger: PaywallTrigger
    var onPurchased: (@MainActor () -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionPlanKind = .yearly
    @State private var purchaseSuccessTrigger = 0
    @State private var safariURL: IdentifiableURL?
    @State private var showRestoreAlert = false

    private var subscriptionManager: SubscriptionManager {
        store.subscriptionManager
    }

    private var yearlyProduct: SubscriptionPlanProduct {
        subscriptionManager.product(for: .yearly)
    }

    private var monthlyProduct: SubscriptionPlanProduct {
        subscriptionManager.product(for: .monthly)
    }

    private var selectedProduct: SubscriptionPlanProduct {
        subscriptionManager.product(for: selectedPlan)
    }

    private var isSelectedTrialEligible: Bool {
        selectedPlan == .yearly
            && selectedProduct.isEligibleForIntroOffer
            && (selectedProduct.introductoryTrialDays ?? 0) > 0
    }

    private var primaryButtonTitle: String {
        if subscriptionManager.isProcessingPurchase {
            return "処理中..."
        }
        if isSelectedTrialEligible, let days = selectedProduct.introductoryTrialDays {
            return "\(days) 日間無料で始める"
        }
        return "プランを始める"
    }

    private var autoRenewalDisclosureText: String {
        if isSelectedTrialEligible, let days = selectedProduct.introductoryTrialDays {
            return "\(days) 日間の無料トライアル終了後、年額 \(selectedProduct.displayPrice) で自動更新されます。現在の期間（または無料トライアル期間）終了の 24 時間前までに解約されない限り自動更新されます。設定アプリからいつでも解約できます。"
        }
        let periodText = selectedPlan == .yearly ? "年額" : "月額"
        return "\(periodText) \(selectedProduct.displayPrice) で自動更新されます。現在の期間終了の 24 時間前までに解約されない限り自動更新されます。設定アプリからいつでも解約できます。"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerSection
                        benefitsSection
                        plansSection

                        if let errorMessage = subscriptionManager.errorMessage {
                            errorBanner(errorMessage)
                        }

                        ctaSection
                        legalAndRestoreSection
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        subscriptionManager.clearMessages()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KumogakureColors.usuzumiText)
                    }
                    .accessibilityLabel("閉じる")
                    .disabled(subscriptionManager.isProcessingPurchase)
                }
            }
            .sensoryFeedback(.success, trigger: purchaseSuccessTrigger)
            .task {
                await subscriptionManager.loadProducts()
            }
            .sheet(item: $safariURL) { item in
                SafariWebView(url: item.url)
                    .ignoresSafeArea()
            }
            .alert("購入の復元", isPresented: $showRestoreAlert) {
                Button("OK") {
                    let wasRestored = subscriptionManager.isPro
                    subscriptionManager.clearMessages()
                    if wasRestored {
                        onPurchased?()
                        dismiss()
                    }
                }
            } message: {
                Text(subscriptionManager.restoreMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProBadge()
                Text("隠者プラン（Pro）")
                    .font(KumogakureTypography.appTitle)
                    .foregroundStyle(KumogakureColors.washiText)
            }

            Text(trigger.reason)
                .font(KumogakureTypography.subheadline)
                .foregroundStyle(KumogakureColors.shinonomeAccent)

            Text("静かな休息の選択肢を広げ、自分の歩みをすべて残せる上位プランです。")
                .font(KumogakureTypography.caption)
                .foregroundStyle(KumogakureColors.usuzumiText)
        }
    }

    private var benefitsSection: some View {
        KumogakureCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                benefitRow(
                    symbol: "mountain.2",
                    title: "すべての風景・環境音を解放（今後の追加素材も含む）"
                )
                benefitRow(
                    symbol: "doc.richtext",
                    title: "不在証明の透かし非表示・限定デザイン・自由な一言"
                )
                benefitRow(
                    symbol: "chart.bar.xaxis",
                    title: "全期間の「雲隠れ帳」履歴と統計グラフ"
                )
                benefitRow(
                    symbol: "heart",
                    title: "個人開発者への静かな応援"
                )
            }
        }
    }

    private func benefitRow(symbol: String, title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(KumogakureColors.shinonomeAccent)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(KumogakureTypography.subheadline)
                .foregroundStyle(KumogakureColors.washiText)
        }
    }

    private var plansSection: some View {
        VStack(spacing: 12) {
            planCard(product: yearlyProduct, isRecommended: true)
            planCard(product: monthlyProduct, isRecommended: false)
        }
    }

    private func planCard(product: SubscriptionPlanProduct, isRecommended: Bool) -> some View {
        let isSelected = (selectedPlan == product.kind)

        return Button {
            selectedPlan = product.kind
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(product.displayName)
                        .font(KumogakureTypography.sectionHeading)
                        .foregroundStyle(KumogakureColors.washiText)

                    if isRecommended {
                        Text("おすすめ")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KumogakureColors.sumiBg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(KumogakureColors.shinonomeAccent))
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder
                        )
                }

                if product.kind == .yearly {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let days = product.introductoryTrialDays, product.isEligibleForIntroOffer {
                            Text("\(days) 日間無料 →")
                                .font(KumogakureTypography.chipLabel)
                                .foregroundStyle(KumogakureColors.shinonomeAccent)
                        }
                        Text("\(product.displayPrice) / 年")
                            .font(KumogakureTypography.chipLabel)
                            .foregroundStyle(KumogakureColors.washiText)
                        if let monthlyEq = product.monthlyEquivalentText {
                            Text("（月あたり \(monthlyEq)）")
                                .font(KumogakureTypography.caption)
                                .foregroundStyle(KumogakureColors.usuzumiText)
                        }
                    }
                } else {
                    Text("\(product.displayPrice) / 月（自動更新・いつでも解約可）")
                        .font(KumogakureTypography.chipLabel)
                        .foregroundStyle(KumogakureColors.washiText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KumogakureColors.yonagaSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder,
                        lineWidth: isSelected ? 1.75 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func errorBanner(_ message: String) -> some View {
        KumogakureCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(KumogakureTypography.caption)
                    .foregroundStyle(KumogakureColors.washiText)
                Button("再試行する") {
                    Task {
                        await startPurchase()
                    }
                }
                .font(KumogakureTypography.caption.weight(.semibold))
                .foregroundStyle(KumogakureColors.shinonomeAccent)
            }
        }
    }

    private var ctaSection: some View {
        Button {
            Task {
                await startPurchase()
            }
        } label: {
            HStack(spacing: 10) {
                if subscriptionManager.isProcessingPurchase {
                    ProgressView()
                        .tint(KumogakureColors.sumiBg)
                }
                Text(primaryButtonTitle)
            }
        }
        .buttonStyle(KumogakurePrimaryButtonStyle())
        .disabled(subscriptionManager.isProcessingPurchase)
    }

    private var legalAndRestoreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(autoRenewalDisclosureText)
                .font(.system(size: 11))
                .foregroundStyle(KumogakureColors.usuzumiText)
                .lineSpacing(4)

            HStack {
                Spacer()
                Button("購入を復元") {
                    Task {
                        _ = await subscriptionManager.restorePurchases()
                        if subscriptionManager.restoreMessage != nil {
                            showRestoreAlert = true
                        }
                    }
                }
                .font(KumogakureTypography.subheadline.weight(.medium))
                .foregroundStyle(KumogakureColors.shinonomeAccent)
                .disabled(subscriptionManager.isProcessingPurchase)
                Spacer()
            }

            HStack(spacing: 16) {
                Spacer()
                Button("利用規約") {
                    safariURL = IdentifiableURL(url: AppConfig.termsOfServiceURL)
                }
                Text("・")
                    .foregroundStyle(KumogakureColors.mistBorder)
                Button("プライバシーポリシー") {
                    safariURL = IdentifiableURL(url: AppConfig.privacyPolicyURL)
                }
                Text("・")
                    .foregroundStyle(KumogakureColors.mistBorder)
                Button("EULA") {
                    safariURL = IdentifiableURL(url: AppConfig.appleStandardEULAURL)
                }
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(KumogakureColors.usuzumiText)
        }
        .padding(.top, 4)
    }

    private func startPurchase() async {
        let succeeded = await subscriptionManager.purchase(plan: selectedPlan)
        if succeeded {
            purchaseSuccessTrigger += 1
            onPurchased?()
            dismiss()
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
