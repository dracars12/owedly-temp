import Foundation
import Adapty

enum PurchasePlan: String, CaseIterable, Hashable {
    case annual
    case weekly

    var displayPeriod: String {
        switch self {
        case .annual: return "year"
        case .weekly: return "week"
        }
    }
}

enum PurchasePlacement: String, Hashable {
    case defaultPaywall = "com.giga.default.placement"
    case specialOffer = "com.giga.special.placement"
}

struct PurchaseProductInfo {
    let plan: PurchasePlan
    let vendorProductId: String
    let localizedTitle: String
    let localizedPrice: String
    let price: Decimal
    let currencyCode: String?
    let localizedSubscriptionPeriod: String?
    let weeklyEquivalentPrice: String?
}

struct PurchasePlacementInfo {
    let placement: PurchasePlacement
    let products: [PurchasePlan: PurchaseProductInfo]
}

struct SpecialOfferInfo {
    let product: PurchaseProductInfo
    let regularAnnualPrice: String?
    let discountPercent: Int?
}

enum PurchaseResult {
    case success
    case cancelled
    case pending
    case failed(String)
}

enum RestorePurchasesResult {
    case restored
    case noActiveSubscription
    case failed(String)
}

extension Notification.Name {
    static let owedlyPurchaseEntitlementDidChange = Notification.Name("owedly.purchase.entitlementDidChange")
    static let owedlyPurchaseStorefrontDidChange = Notification.Name("owedly.purchase.storefrontDidChange")
}

/// The single source of truth for Owedly Premium.
///
/// Adapty owns receipt validation and subscription state. The UI only reads `isPurchased` and
/// reacts to `owedlyPurchaseEntitlementDidChange`, so every screen stays synchronized when a
/// purchase, restore, renewal, expiration or refund changes the profile.
final class PurchaseManager: NSObject {
    static let shared = PurchaseManager()

    private let publicSDKKey = "public_live_dDBWX9X7.zTY7P592B9iiENdH20hV"
    private let preferredAccessLevelID = "premium"
    private let lock = NSLock()

    private var activationTask: Task<Void, Error>?
    private var activationGeneration = 0
    private var entitlementActive = false
    // StoreKit/Adapty can report a successful purchase before the returned profile has refreshed
    // its access levels. Keep Premium unlocked for the remainder of that app session after a
    // confirmed purchase and wait for a later active profile to become the authoritative state.
    // This prevents a real App Store purchase from being surfaced to the user as "Purchase failed".
    private var purchaseAwaitingProfileConfirmation = false
    private var cachedFlows: [PurchasePlacement: AdaptyFlow] = [:]
    private var cachedProducts: [PurchasePlacement: [AdaptyPaywallProduct]] = [:]
    private var cachedPlacementInfos: [PurchasePlacement: PurchasePlacementInfo] = [:]
    private var cachedSpecialOfferInfo: SpecialOfferInfo?

    private let storefrontCacheKey = "owedly.purchase.storefrontCache.v1"

    private override init() {
        super.init()
        restorePersistedStorefrontCache()
    }

    var isPurchased: Bool {
        lock.owedlyWithLock { entitlementActive }
    }

    /// Last successfully resolved StoreKit/Adapty metadata. It is restored from disk on launch,
    /// so paywalls and promo surfaces can render real prices immediately while a fresh network
    /// refresh happens in the background.
    func cachedPlacement(_ placement: PurchasePlacement) -> PurchasePlacementInfo? {
        lock.owedlyWithLock { cachedPlacementInfos[placement] }
    }

    func cachedSpecialOffer() -> SpecialOfferInfo? {
        lock.owedlyWithLock { cachedSpecialOfferInfo }
    }

    /// Starts Adapty as early as possible, then warms both placements and the current profile.
    /// Nothing in the visible UI needs to be the first caller that touches StoreKit.
    func configureAtLaunch() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureActivated()
                await self.prefetchStorefrontData()
                await self.refreshSubscriptionStatus()
            } catch {
                print("[Adapty] Activation failed: \(error.localizedDescription)")
            }
        }
    }

    /// Called whenever the app returns to the foreground. Renewals/refunds and App Store pricing
    /// can both change while Owedly is inactive, so refresh entitlement + product metadata together.
    func refreshForForeground() async {
        await prefetchStorefrontData()
        await refreshSubscriptionStatus()
    }

    func prefetchStorefrontData() async {
        do {
            _ = try await loadPlacement(.defaultPaywall)
        } catch {
            print("[Adapty] Default placement prefetch failed: \(error.localizedDescription)")
        }

        do {
            _ = try await loadSpecialOffer()
        } catch {
            print("[Adapty] Special offer prefetch failed: \(error.localizedDescription)")
        }
    }

    /// Force-refreshes subscription state. Called on launch and every foreground transition.
    func refreshSubscriptionStatus() async {
        do {
            try await ensureActivated()
            let profile = try await Adapty.getProfile()
            apply(profile: profile)
        } catch {
            print("[Adapty] Profile refresh failed: \(error.localizedDescription)")
        }
    }

    /// Fetches the current flow selected by Adapty for this placement and its App Store products.
    /// Adapty's default fetch policy revalidates its cache, while we retain the exact flow/product
    /// objects used by the visible custom paywall for impression logging and checkout.
    func loadPlacement(_ placement: PurchasePlacement) async throws -> PurchasePlacementInfo {
        try await ensureActivated()

        let flow = try await Adapty.getFlow(placementId: placement.rawValue)
        let products = try await Adapty.getPaywallProducts(flow: flow)

        let info = PurchasePlacementInfo(
            placement: placement,
            products: mapProducts(products, placement: placement)
        )

        lock.owedlyWithLock {
            cachedFlows[placement] = flow
            cachedProducts[placement] = products
            cachedPlacementInfos[placement] = info
        }
        persistStorefrontCache()
        postStorefrontDidChange()

        return info
    }

    /// Loads the discounted annual product plus the regular annual price used by the default
    /// placement. This keeps the special-offer UI fully driven by App Store / Adapty data.
    func loadSpecialOffer() async throws -> SpecialOfferInfo {
        let special = try await loadPlacement(.specialOffer)
        guard let specialAnnual = special.products[.annual] else {
            throw PurchaseManagerError.missingProduct("annual product in \(PurchasePlacement.specialOffer.rawValue)")
        }

        let regularAnnual: PurchaseProductInfo?
        if let cachedAnnual = cachedPlacement(.defaultPaywall)?.products[.annual] {
            regularAnnual = cachedAnnual
        } else {
            do {
                regularAnnual = try await loadPlacement(.defaultPaywall).products[.annual]
            } catch {
                print("[Adapty] Regular annual comparison price unavailable: \(error.localizedDescription)")
                regularAnnual = nil
            }
        }

        let discountPercent: Int? = {
            guard let regularAnnual,
                  regularAnnual.price > 0,
                  specialAnnual.price < regularAnnual.price else { return nil }
            let regular = NSDecimalNumber(decimal: regularAnnual.price)
            let specialPrice = NSDecimalNumber(decimal: specialAnnual.price)
            let fraction = NSDecimalNumber.one.subtracting(specialPrice.dividing(by: regular))
            return max(0, min(100, Int((fraction.doubleValue * 100).rounded())))
        }()

        let info = SpecialOfferInfo(
            product: specialAnnual,
            regularAnnualPrice: regularAnnual?.localizedPrice,
            discountPercent: discountPercent
        )
        lock.owedlyWithLock { cachedSpecialOfferInfo = info }
        persistStorefrontCache()
        postStorefrontDidChange()
        return info
    }

    /// Custom paywalls must report their presentation to Adapty explicitly.
    func logPresentation(for placement: PurchasePlacement) async {
        do {
            try await ensureActivated()
            var flow = lock.owedlyWithLock { cachedFlows[placement] }
            if flow == nil {
                _ = try await loadPlacement(placement)
                flow = lock.owedlyWithLock { cachedFlows[placement] }
            }
            guard let flow else { return }
            try await Adapty.logShowFlow(flow)
        } catch {
            // Impression logging must never block a purchase-capable screen.
            print("[Adapty] Failed to log \(placement.rawValue) presentation: \(error.localizedDescription)")
        }
    }

    func purchase(
        _ plan: PurchasePlan,
        placement: PurchasePlacement = .defaultPaywall
    ) async -> PurchaseResult {
        do {
            try await ensureActivated()
            let product = try await rawProduct(for: plan, placement: placement)
            let result = try await Adapty.makePurchase(product: product)

            switch result {
            case .userCancelled:
                print("[Adapty][Purchase] Cancelled product=\(product.vendorProductId) placement=\(placement.rawValue)")
                return .cancelled

            case .pending:
                print("[Adapty][Purchase] Pending product=\(product.vendorProductId) placement=\(placement.rawValue)")
                return .pending

            case let .success(profile, _):
                // `.success` means the App Store transaction completed. Do not turn that into a
                // user-visible failure just because Adapty's profile in this exact response has
                // not propagated the entitlement yet (this can happen in Sandbox/App Review).
                apply(profile: profile)

                if hasPremiumAccess(profile) {
                    print("[Adapty][Purchase] Success + entitlement confirmed product=\(product.vendorProductId)")
                    return .success
                }

                print("[Adapty][Purchase] Success, entitlement propagation delayed product=\(product.vendorProductId). Unlocking optimistically and refreshing profile.")
                markSuccessfulPurchaseAwaitingProfileConfirmation()
                await refreshProfileAfterSuccessfulPurchase()
                return .success
            }
        } catch {
            let nsError = error as NSError
            print("[Adapty][Purchase] Failed plan=\(plan.rawValue) placement=\(placement.rawValue) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> RestorePurchasesResult {
        do {
            try await ensureActivated()
            let profile = try await Adapty.restorePurchases()
            apply(profile: profile)
            return hasPremiumAccess(profile) ? .restored : .noActiveSubscription
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Analytics integrations

    /// Adapty's Firebase integration requires the Firebase App Instance ID on the active profile.
    /// Run this once per app launch, before purchase flows, after both SDKs are initialized.
    func linkFirebaseAppInstanceID(_ appInstanceID: String) async {
        guard !appInstanceID.isEmpty else { return }
        do {
            try await ensureActivated()
            try await Adapty.setIntegrationIdentifier(.firebaseAppInstanceId(appInstanceID))
        } catch {
            print("[Adapty] Firebase integration identifier failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors the Cleaner AppsFlyer -> Adapty bridge using the current Adapty 4.1 API names.
    /// The AppsFlyer UID is attached first, then install attribution is forwarded to Adapty.
    func linkAppsFlyer(
        uid: String,
        conversionData: [AnyHashable: Any]
    ) async {
        guard !uid.isEmpty else { return }
        do {
            try await ensureActivated()
            try await Adapty.setIntegrationIdentifier(.appsflyerId(uid))
            try await Adapty.updateExternalAttribution(conversionData, provider: .appsflyer)
        } catch {
            print("[Adapty] AppsFlyer integration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Adapty setup

    private func ensureActivated() async throws {
        let (task, generation): (Task<Void, Error>, Int) = lock.owedlyWithLock {
            if let activationTask { return (activationTask, activationGeneration) }

            activationGeneration += 1
            let generation = activationGeneration
            let task = Task { [weak self] in
                guard let self else { return }
                let configuration = AdaptyConfiguration
                    .builder(withAPIKey: self.publicSDKKey)
                    .with(logLevel: .info)
                    // ATT is requested by AnalyticsCoordinator before AppsFlyer's first session.
                    // Adapty can therefore collect IDFA when Apple authorizes it, matching the
                    // sequencing used in Cleaner while still respecting a denied ATT status.
                    .with(idfaCollectionDisabled: false)
                    .with(ipAddressCollectionDisabled: false)
                    .build()

                try await Adapty.activate(with: configuration)
                Adapty.delegate = self
            }
            activationTask = task
            return (task, generation)
        }

        do {
            try await task.value
        } catch {
            // Do not permanently poison the manager after a transient activation failure. Clear
            // only the failed generation so a later foreground / paywall request can retry, while
            // another concurrent waiter cannot accidentally discard a newer activation attempt.
            lock.owedlyWithLock {
                if activationGeneration == generation {
                    activationTask = nil
                }
            }
            throw error
        }
    }

    // MARK: - Product mapping

    private func rawProduct(
        for plan: PurchasePlan,
        placement: PurchasePlacement
    ) async throws -> AdaptyPaywallProduct {
        var products = lock.owedlyWithLock { cachedProducts[placement] }
        if products == nil {
            _ = try await loadPlacement(placement)
            products = lock.owedlyWithLock { cachedProducts[placement] }
        }

        guard let products else {
            throw PurchaseManagerError.missingProduct("products in \(placement.rawValue)")
        }

        if let exact = products.first(where: { inferredPlan(for: $0, placement: placement) == plan }) {
            return exact
        }

        // The special placement is intentionally annual-only. If App Store metadata has not yet
        // exposed its subscription period, the sole configured product is still unambiguous.
        if placement == .specialOffer, plan == .annual, products.count == 1, let only = products.first {
            return only
        }

        throw PurchaseManagerError.missingProduct("\(plan.rawValue) product in \(placement.rawValue)")
    }

    private func mapProducts(
        _ products: [AdaptyPaywallProduct],
        placement: PurchasePlacement
    ) -> [PurchasePlan: PurchaseProductInfo] {
        var mapped: [PurchasePlan: PurchaseProductInfo] = [:]

        for product in products {
            guard let plan = inferredPlan(for: product, placement: placement) else { continue }
            mapped[plan] = makeProductInfo(from: product, plan: plan, placement: placement)
        }

        if placement == .specialOffer,
           mapped[.annual] == nil,
           products.count == 1,
           let only = products.first {
            mapped[.annual] = makeProductInfo(from: only, plan: .annual, placement: placement)
        }

        return mapped
    }

    private func inferredPlan(
        for product: AdaptyPaywallProduct,
        placement: PurchasePlacement
    ) -> PurchasePlan? {
        if let period = product.subscriptionPeriod {
            switch period.unit {
            case .year where period.numberOfUnits == 1:
                return .annual
            case .week where period.numberOfUnits == 1:
                return .weekly
            default:
                break
            }
        }

        let identifier = product.vendorProductId.lowercased()
        if identifier.contains("week") { return .weekly }
        if identifier.contains("annual") || identifier.contains("year") { return .annual }
        if placement == .specialOffer { return .annual }
        return nil
    }

    private func makeProductInfo(
        from product: AdaptyPaywallProduct,
        plan: PurchasePlan,
        placement: PurchasePlacement
    ) -> PurchaseProductInfo {
        // A special Adapty placement may point either to a separately priced annual SKU or to
        // the same annual SKU with an eligible App Store promotional / win-back offer attached.
        // `getPaywallProducts(flow:)` resolves offer eligibility for the current customer, and
        // `makePurchase` applies that active offer automatically. Mirror the same effective price
        // in our custom UI so the amount shown before checkout matches what Adapty will purchase.
        let activeDiscountOffer = placement == .specialOffer
            ? product.subscriptionOffer.flatMap { offer in
                offer.price > 0 && offer.price < product.price ? offer : nil
            }
            : nil

        let effectivePrice = activeDiscountOffer?.price ?? product.price
        let effectiveCurrencyCode = activeDiscountOffer?.currencyCode ?? product.currencyCode
        let localizedPrice = activeDiscountOffer?.localizedPrice
            ?? product.localizedPrice
            ?? Self.currencyString(for: effectivePrice, dividedBy: 1, currencyCode: effectiveCurrencyCode)
            ?? NSDecimalNumber(decimal: effectivePrice).stringValue

        return PurchaseProductInfo(
            plan: plan,
            vendorProductId: product.vendorProductId,
            localizedTitle: product.localizedTitle,
            localizedPrice: localizedPrice,
            price: effectivePrice,
            currencyCode: effectiveCurrencyCode,
            localizedSubscriptionPeriod: activeDiscountOffer?.localizedSubscriptionPeriod
                ?? product.localizedSubscriptionPeriod,
            weeklyEquivalentPrice: plan == .annual
                ? Self.currencyString(for: effectivePrice, dividedBy: 52, currencyCode: effectiveCurrencyCode)
                : nil
        )
    }

    private static func currencyString(
        for price: Decimal,
        dividedBy divisor: Int,
        currencyCode: String?
    ) -> String? {
        guard divisor > 0 else { return nil }
        let weekly = NSDecimalNumber(decimal: price).dividing(by: NSDecimalNumber(value: divisor))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        if let currencyCode, !currencyCode.isEmpty {
            formatter.currencyCode = currencyCode
        }
        return formatter.string(from: weekly)
    }

    // MARK: - Storefront cache

    private struct PersistedStorefrontCache: Codable {
        let localeIdentifier: String
        let placements: [PersistedPlacement]
        let specialOffer: PersistedSpecialOffer?
    }

    private struct PersistedPlacement: Codable {
        let placement: String
        let products: [PersistedProduct]
    }

    private struct PersistedProduct: Codable {
        let plan: String
        let vendorProductId: String
        let localizedTitle: String
        let localizedPrice: String
        let price: String
        let currencyCode: String?
        let localizedSubscriptionPeriod: String?
        let weeklyEquivalentPrice: String?

        init(_ value: PurchaseProductInfo) {
            plan = value.plan.rawValue
            vendorProductId = value.vendorProductId
            localizedTitle = value.localizedTitle
            localizedPrice = value.localizedPrice
            price = NSDecimalNumber(decimal: value.price).stringValue
            currencyCode = value.currencyCode
            localizedSubscriptionPeriod = value.localizedSubscriptionPeriod
            weeklyEquivalentPrice = value.weeklyEquivalentPrice
        }

        var productInfo: PurchaseProductInfo? {
            guard let plan = PurchasePlan(rawValue: plan),
                  let decimal = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return PurchaseProductInfo(
                plan: plan,
                vendorProductId: vendorProductId,
                localizedTitle: localizedTitle,
                localizedPrice: localizedPrice,
                price: decimal,
                currencyCode: currencyCode,
                localizedSubscriptionPeriod: localizedSubscriptionPeriod,
                weeklyEquivalentPrice: weeklyEquivalentPrice
            )
        }
    }

    private struct PersistedSpecialOffer: Codable {
        let product: PersistedProduct
        let regularAnnualPrice: String?
        let discountPercent: Int?
    }

    private func persistStorefrontCache() {
        let snapshot: PersistedStorefrontCache = lock.owedlyWithLock {
            let placements = cachedPlacementInfos.values.map { info in
                PersistedPlacement(
                    placement: info.placement.rawValue,
                    products: info.products.values.map(PersistedProduct.init)
                )
            }
            let special = cachedSpecialOfferInfo.map {
                PersistedSpecialOffer(
                    product: PersistedProduct($0.product),
                    regularAnnualPrice: $0.regularAnnualPrice,
                    discountPercent: $0.discountPercent
                )
            }
            return PersistedStorefrontCache(
                localeIdentifier: Locale.current.identifier,
                placements: placements,
                specialOffer: special
            )
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storefrontCacheKey)
    }

    private func restorePersistedStorefrontCache() {
        guard let data = UserDefaults.standard.data(forKey: storefrontCacheKey),
              let snapshot = try? JSONDecoder().decode(PersistedStorefrontCache.self, from: data),
              snapshot.localeIdentifier == Locale.current.identifier else { return }

        var placements: [PurchasePlacement: PurchasePlacementInfo] = [:]
        for persistedPlacement in snapshot.placements {
            guard let placement = PurchasePlacement(rawValue: persistedPlacement.placement) else { continue }
            var products: [PurchasePlan: PurchaseProductInfo] = [:]
            for persistedProduct in persistedPlacement.products {
                guard let product = persistedProduct.productInfo else { continue }
                products[product.plan] = product
            }
            guard !products.isEmpty else { continue }
            placements[placement] = PurchasePlacementInfo(placement: placement, products: products)
        }

        let special: SpecialOfferInfo? = snapshot.specialOffer.flatMap { persisted in
            guard let product = persisted.product.productInfo else { return nil }
            return SpecialOfferInfo(
                product: product,
                regularAnnualPrice: persisted.regularAnnualPrice,
                discountPercent: persisted.discountPercent
            )
        }

        lock.owedlyWithLock {
            cachedPlacementInfos = placements
            cachedSpecialOfferInfo = special
        }
    }

    private func postStorefrontDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .owedlyPurchaseStorefrontDidChange, object: nil)
        }
    }

    // MARK: - Entitlement state

    private func hasPremiumAccess(_ profile: AdaptyProfile) -> Bool {
        if let premium = profile.accessLevels[preferredAccessLevelID] {
            return premium.isActive
        }
        // Keep the app usable if the Dashboard uses one custom access-level ID instead of the
        // default `premium`. With a single-access-level app, any active level means Premium.
        return profile.accessLevels.values.contains(where: { $0.isActive })
    }

    private func markSuccessfulPurchaseAwaitingProfileConfirmation() {
        let changed = lock.owedlyWithLock { () -> Bool in
            purchaseAwaitingProfileConfirmation = true
            guard !entitlementActive else { return false }
            entitlementActive = true
            return true
        }

        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .owedlyPurchaseEntitlementDidChange, object: nil)
        }
    }

    /// Sandbox/App Review can occasionally lag between a completed StoreKit transaction and the
    /// updated Adapty profile. Retry briefly so the optimistic unlock is replaced by confirmed
    /// server state as quickly as possible. A failed refresh must never undo a completed purchase
    /// during the current app session; the next cold launch starts without this optimistic flag
    /// and resolves the latest profile normally.
    private func refreshProfileAfterSuccessfulPurchase() async {
        let delays: [UInt64] = [250_000_000, 500_000_000, 1_000_000_000, 1_500_000_000]

        for delay in delays {
            try? await Task<Never, Never>.sleep(nanoseconds: delay)

            do {
                let profile = try await Adapty.getProfile()
                apply(profile: profile)
                if hasPremiumAccess(profile) {
                    print("[Adapty][Purchase] Entitlement confirmed after delayed profile refresh.")
                    return
                }
            } catch {
                let nsError = error as NSError
                print("[Adapty][Purchase] Post-purchase profile refresh failed domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
            }
        }

        print("[Adapty][Purchase] Transaction succeeded but profile entitlement is still propagating. Keeping Premium unlocked for this session.")
    }

    private func apply(profile: AdaptyProfile) {
        let profileHasPremium = hasPremiumAccess(profile)
        let changed = lock.owedlyWithLock { () -> Bool in
            if profileHasPremium {
                purchaseAwaitingProfileConfirmation = false
            } else if purchaseAwaitingProfileConfirmation {
                // A stale profile immediately after a confirmed purchase must not revoke the
                // optimistic unlock or create a false "Purchase failed" experience.
                return false
            }

            guard entitlementActive != profileHasPremium else { return false }
            entitlementActive = profileHasPremium
            return true
        }

        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .owedlyPurchaseEntitlementDidChange, object: nil)
        }
    }
}

extension PurchaseManager: AdaptyDelegate {
    nonisolated func didLoadLatestProfile(_ profile: AdaptyProfile) {
        apply(profile: profile)
    }
}

private enum PurchaseManagerError: LocalizedError {
    case missingProduct(String)

    var errorDescription: String? {
        switch self {
        case let .missingProduct(description):
            return "Adapty could not load the configured \(description). Check that the placement and products are published in Adapty and available in App Store Connect."
        }
    }
}

private extension NSLock {
    func owedlyWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
