import Foundation
import Observation
import StoreKit

enum SubscriptionPlanKind: String, CaseIterable, Identifiable, Sendable {
    case yearly
    case monthly

    var id: String { productID }

    var productID: String {
        switch self {
        case .yearly: return AppConfig.yearlyProductID
        case .monthly: return AppConfig.monthlyProductID
        }
    }

    var title: String {
        switch self {
        case .yearly: return "年額プラン"
        case .monthly: return "月額プラン"
        }
    }

    var billingPeriodLabel: String {
        switch self {
        case .yearly: return "年"
        case .monthly: return "月"
        }
    }

    var fallbackDisplayPrice: String {
        switch self {
        case .yearly: return "¥2,400"
        case .monthly: return "¥300"
        }
    }

    var fallbackMonthlyEquivalent: String? {
        switch self {
        case .yearly: return "¥200"
        case .monthly: return nil
        }
    }

    var fallbackTrialDays: Int? {
        switch self {
        case .yearly: return 7
        case .monthly: return nil
        }
    }
}

struct SubscriptionPlanProduct: Equatable, Identifiable, Sendable {
    let kind: SubscriptionPlanKind
    let id: String
    let displayName: String
    let displayPrice: String
    let monthlyEquivalentText: String?
    let introductoryTrialDays: Int?
    let isEligibleForIntroOffer: Bool

    static func fallback(for kind: SubscriptionPlanKind) -> SubscriptionPlanProduct {
        SubscriptionPlanProduct(
            kind: kind,
            id: kind.productID,
            displayName: kind.title,
            displayPrice: kind.fallbackDisplayPrice,
            monthlyEquivalentText: kind.fallbackMonthlyEquivalent,
            introductoryTrialDays: kind.fallbackTrialDays,
            isEligibleForIntroOffer: kind.fallbackTrialDays != nil
        )
    }

    static var fallbackCatalog: [SubscriptionPlanProduct] {
        [fallback(for: .yearly), fallback(for: .monthly)]
    }
}

struct EntitlementSnapshot: Equatable, Sendable {
    let entitlementID: String
    let isActive: Bool
    let activeProductID: String?
    let expirationDate: Date?

    static let inactive = EntitlementSnapshot(
        entitlementID: AppConfig.entitlementID,
        isActive: false,
        activeProductID: nil,
        expirationDate: nil
    )
}

enum PurchaseOutcome: Equatable, Sendable {
    case purchased(EntitlementSnapshot)
    case userCancelled
    case pending
}

enum BillingError: Error, LocalizedError, Equatable, Sendable {
    case productUnavailable
    case verificationFailed
    case storeError(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "プラン情報を取得できませんでした。通信環境をご確認のうえ再度お試しください。"
        case .verificationFailed:
            return "購入情報の検証に失敗しました。時間をおいて再度お試しください。"
        case .storeError(let message):
            return message
        }
    }
}

enum PaywallTrigger: Identifiable, Equatable, Sendable {
    case theme(ThemeID)
    case sound(SoundID)
    case purposeCustom
    case cardStyle(CardStyle)
    case hideWatermark
    case historyLocked
    case historyAnalytics
    case settingsUpgrade
    case milestoneBanner

    var id: String {
        switch self {
        case .theme(let theme): return "theme_\(theme.rawValue)"
        case .sound(let sound): return "sound_\(sound.rawValue)"
        case .purposeCustom: return "purpose_custom"
        case .cardStyle(let style): return "card_style_\(style.rawValue)"
        case .hideWatermark: return "hide_watermark"
        case .historyLocked: return "history_locked"
        case .historyAnalytics: return "history_analytics"
        case .settingsUpgrade: return "settings_upgrade"
        case .milestoneBanner: return "milestone_banner"
        }
    }

    var reason: String {
        switch self {
        case .theme(let theme):
            return "「\(theme.displayName)」は隠者プランで解放されます"
        case .sound(let sound):
            return "環境音「\(sound.displayName)」は隠者プランで解放されます"
        case .purposeCustom:
            return "自由な一言は隠者プランで解放されます"
        case .cardStyle(let style):
            return "デザイン「\(style.displayName)」は隠者プランで解放されます"
        case .hideWatermark:
            return "透かし非表示は隠者プランで解放されます"
        case .historyLocked:
            return "これより先の雲隠れ帳は「隠者プラン」で開けます"
        case .historyAnalytics:
            return "曜日別・時間帯別の統計グラフは隠者プランで解放されます"
        case .settingsUpgrade:
            return "すべての風景・環境音と雲隠れ帳の全履歴を解放できます"
        case .milestoneBanner:
            return "すべての風景・環境音と雲隠れ帳の全履歴を解放できます"
        }
    }
}

// MARK: - Billing Provider Abstraction

protocol BillingProviding: Sendable {
    func loadProducts() async throws -> [SubscriptionPlanProduct]
    func currentEntitlement() async -> EntitlementSnapshot
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restorePurchases() async throws -> EntitlementSnapshot
    func startObservingUpdates(
        onUpdate: @escaping @Sendable (EntitlementSnapshot) async -> Void
    ) -> Task<Void, Never>
}

/// StoreKit 2 billing backend supporting local `.storekit` configuration in Week 4.
/// RevenueCat SDK integration wraps the same `hermit_pro` entitlement boundary in Week 5.
final class StoreKitBillingClient: BillingProviding, Sendable {
    private let productIDs: [String]
    private let entitlementID: String

    init(
        productIDs: [String] = [AppConfig.yearlyProductID, AppConfig.monthlyProductID],
        entitlementID: String = AppConfig.entitlementID
    ) {
        self.productIDs = productIDs
        self.entitlementID = entitlementID
    }

    func loadProducts() async throws -> [SubscriptionPlanProduct] {
        let storeProducts = try await Product.products(for: productIDs)
        var mapped: [SubscriptionPlanProduct] = []

        for kind in SubscriptionPlanKind.allCases {
            guard let product = storeProducts.first(where: { $0.id == kind.productID }) else {
                continue
            }
            let trialDays = Self.freeTrialDays(for: product)
            let isEligible: Bool
            if trialDays != nil, let subscription = product.subscription {
                isEligible = await subscription.isEligibleForIntroOffer
            } else {
                isEligible = false
            }

            let monthlyEquivalent: String? = if kind == .yearly {
                (product.price / Decimal(12)).formatted(product.priceFormatStyle)
            } else {
                nil
            }

            mapped.append(
                SubscriptionPlanProduct(
                    kind: kind,
                    id: product.id,
                    displayName: kind.title,
                    displayPrice: product.displayPrice,
                    monthlyEquivalentText: monthlyEquivalent,
                    introductoryTrialDays: trialDays,
                    isEligibleForIntroOffer: isEligible
                )
            )
        }

        return mapped
    }

    func currentEntitlement() async -> EntitlementSnapshot {
        let targetIDs = Set(productIDs)
        var bestTransaction: Transaction?
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard targetIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                continue
            }

            if let currentBest = bestTransaction {
                let currentExp = currentBest.expirationDate ?? .distantFuture
                let nextExp = transaction.expirationDate ?? .distantFuture
                if nextExp > currentExp {
                    bestTransaction = transaction
                }
            } else {
                bestTransaction = transaction
            }
        }

        guard let active = bestTransaction else {
            return EntitlementSnapshot(
                entitlementID: entitlementID,
                isActive: false,
                activeProductID: nil,
                expirationDate: nil
            )
        }

        return EntitlementSnapshot(
            entitlementID: entitlementID,
            isActive: true,
            activeProductID: active.productID,
            expirationDate: active.expirationDate
        )
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw BillingError.productUnavailable
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw BillingError.storeError(error.localizedDescription)
        }

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                let snapshot = await currentEntitlement()
                return .purchased(snapshot)
            case .unverified:
                throw BillingError.verificationFailed
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws -> EntitlementSnapshot {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    func startObservingUpdates(
        onUpdate: @escaping @Sendable (EntitlementSnapshot) async -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                guard let self else { break }
                let snapshot = await self.currentEntitlement()
                await onUpdate(snapshot)
            }
        }
    }

    private static func freeTrialDays(for product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return nil
        }
        let period = offer.period
        switch period.unit {
        case .day:
            return period.value
        case .week:
            return period.value * 7
        case .month:
            return period.value * 30
        case .year:
            return period.value * 365
        @unknown default:
            return nil
        }
    }
}

// MARK: - Observable Subscription Manager

@Observable
@MainActor
final class SubscriptionManager {
    private let billing: any BillingProviding
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private(set) var products: [SubscriptionPlanProduct] = []
    private(set) var entitlement: EntitlementSnapshot = .inactive
    private(set) var isLoadingProducts: Bool = false
    private(set) var isProcessingPurchase: Bool = false
    private(set) var errorMessage: String?
    private(set) var restoreMessage: String?
    private(set) var activeAppUserID: String?

    var onEntitlementChanged: ((Bool) -> Void)?

    var isPro: Bool {
        entitlement.isActive
    }

    var displayProducts: [SubscriptionPlanProduct] {
        products.isEmpty ? SubscriptionPlanProduct.fallbackCatalog : products
    }

    init(billing: any BillingProviding = StoreKitBillingClient()) {
        self.billing = billing
    }

    deinit {
        updatesTask?.cancel()
    }

    func product(for kind: SubscriptionPlanKind) -> SubscriptionPlanProduct {
        displayProducts.first(where: { $0.kind == kind }) ?? .fallback(for: kind)
    }

    func start(appUserID: String) async {
        activeAppUserID = appUserID
        if !hasStarted {
            hasStarted = true
            updatesTask = billing.startObservingUpdates { [weak self] snapshot in
                await MainActor.run {
                    self?.applyEntitlement(snapshot)
                }
            }
        }

        async let entitlementFetch = billing.currentEntitlement()
        async let productsFetch: Void = loadProducts()

        let snapshot = await entitlementFetch
        applyEntitlement(snapshot)
        await productsFetch
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await billing.loadProducts()
            if !loaded.isEmpty {
                products = loaded
            }
        } catch {
            // Keep fallback display pricing when StoreKit catalog cannot be loaded.
        }
    }

    func refreshEntitlement() async {
        let snapshot = await billing.currentEntitlement()
        applyEntitlement(snapshot)
    }

    @discardableResult
    func purchase(plan: SubscriptionPlanKind) async -> Bool {
        guard !isProcessingPurchase else { return false }
        isProcessingPurchase = true
        errorMessage = nil
        restoreMessage = nil
        defer { isProcessingPurchase = false }

        do {
            let outcome = try await billing.purchase(productID: plan.productID)
            switch outcome {
            case .purchased(let snapshot):
                applyEntitlement(snapshot)
                return snapshot.isActive
            case .userCancelled:
                // Never show an error alert when the user cancels StoreKit sheet (`ux-and-screens.md` S-07).
                return false
            case .pending:
                errorMessage = "購入の承認待ちです。承認完了後に自動で反映されます。"
                return false
            }
        } catch let billingError as BillingError {
            errorMessage = billingError.localizedDescription
            return false
        } catch {
            errorMessage = "購入処理中にエラーが発生しました。通信環境をご確認のうえ再度お試しください。"
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isProcessingPurchase else { return false }
        isProcessingPurchase = true
        errorMessage = nil
        restoreMessage = nil
        defer { isProcessingPurchase = false }

        do {
            let snapshot = try await billing.restorePurchases()
            applyEntitlement(snapshot)
            if snapshot.isActive {
                restoreMessage = "隠者プランを復元しました。"
                return true
            } else {
                restoreMessage = "復元可能な購入履歴は見つかりませんでした。"
                return false
            }
        } catch {
            errorMessage = "購入の復元に失敗しました。通信環境をご確認のうえ再度お試しください。"
            return false
        }
    }

    func clearMessages() {
        errorMessage = nil
        restoreMessage = nil
    }

    private func applyEntitlement(_ snapshot: EntitlementSnapshot) {
        let previousIsPro = entitlement.isActive
        entitlement = snapshot
        if previousIsPro != snapshot.isActive {
            onEntitlementChanged?(snapshot.isActive)
        }
    }
}
