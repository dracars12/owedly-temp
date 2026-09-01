import Foundation

// MARK: - Settlement domain model

struct Settlement: Hashable, Codable {
    enum Status: String, Codable {
        case open
        case upcoming
        case closed
        case unknown

        init(rawValueLenient value: String?) {
            switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "open", "active": self = .open
            case "upcoming", "coming_soon", "coming soon": self = .upcoming
            case "closed", "expired": self = .closed
            default: self = .unknown
            }
        }
    }

    let id: String
    let title: String
    let company: String
    let shortDescription: String
    let eligibilityDescription: String?
    let category: String
    let payoutText: String?
    let deadline: Date?
    let proofRequired: Bool?
    let eligibleStates: [String]
    let isNationwide: Bool
    let classPeriodText: String?
    let officialClaimURL: URL?
    let sourceURL: URL?
    let imageURL: URL?
    let status: Status
    let createdAt: Date?
    let updatedAt: Date?
    let isFeatured: Bool
    let sourceRank: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, company, shortDescription, eligibilityDescription, category
        case payoutText, deadline, proofRequired, eligibleStates, isNationwide, classPeriodText
        case officialClaimURL, sourceURL, imageURL, status, createdAt, updatedAt, isFeatured, sourceRank
    }

    init(
        id: String,
        title: String,
        company: String,
        shortDescription: String,
        eligibilityDescription: String? = nil,
        category: String,
        payoutText: String? = nil,
        deadline: Date? = nil,
        proofRequired: Bool? = nil,
        eligibleStates: [String] = [],
        isNationwide: Bool = false,
        classPeriodText: String? = nil,
        officialClaimURL: URL? = nil,
        sourceURL: URL? = nil,
        imageURL: URL? = nil,
        status: Status = .open,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        isFeatured: Bool = false,
        sourceRank: Int = Int.max
    ) {
        self.id = id
        self.title = title
        self.company = company
        self.shortDescription = shortDescription
        self.eligibilityDescription = eligibilityDescription
        self.category = category
        self.payoutText = payoutText
        self.deadline = deadline
        self.proofRequired = proofRequired
        self.eligibleStates = eligibleStates
        self.isNationwide = isNationwide
        self.classPeriodText = classPeriodText
        self.officialClaimURL = officialClaimURL
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFeatured = isFeatured
        self.sourceRank = sourceRank
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        company = try container.decode(String.self, forKey: .company)
        shortDescription = try container.decode(String.self, forKey: .shortDescription)
        eligibilityDescription = try container.decodeIfPresent(String.self, forKey: .eligibilityDescription)
        category = try container.decode(String.self, forKey: .category)
        payoutText = try container.decodeIfPresent(String.self, forKey: .payoutText)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        proofRequired = try container.decodeIfPresent(Bool.self, forKey: .proofRequired)

        // Realtime Database does not persist an empty array/object as a child node.
        // Therefore `eligibleStates: []` from an imported JSON snapshot comes back as a
        // missing key. Treat that Firebase-normalized representation as the intended empty array.
        eligibleStates = try container.decodeIfPresent([String].self, forKey: .eligibleStates) ?? []
        isNationwide = try container.decodeIfPresent(Bool.self, forKey: .isNationwide) ?? false

        classPeriodText = try container.decodeIfPresent(String.self, forKey: .classPeriodText)
        officialClaimURL = try container.decodeIfPresent(URL.self, forKey: .officialClaimURL)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .unknown
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        isFeatured = try container.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        sourceRank = try container.decodeIfPresent(Int.self, forKey: .sourceRank) ?? Int.max
    }
}


// MARK: - Data loading

enum SettlementDataSource: Equatable {
    case firebase
    case classActionWebsite
    case localCache
    case bundledFallback
    case demoBecauseAllSourcesFailed
}

enum SettlementRefreshPolicy: Equatable {
    /// Uses a fresh local cache first, otherwise refreshes from the configured website.
    /// There is intentionally no public force-refresh path: live catalog requests are capped
    /// by the scanner cache TTL to avoid unnecessary source traffic.
    case preferFreshCache
    /// Never performs network catalog loading; useful for instant/offline screens.
    case cacheOnly
}

struct SettlementFetchResult {
    let settlements: [Settlement]
    let source: SettlementDataSource
    let warning: String?
}

final class SettlementDataManager {
    static let shared = SettlementDataManager()

    private let websiteScanner: SettlementWebsiteScanner
    private let firebaseCatalogStore: FirebaseSettlementCatalogStore
    private let cacheStore: SettlementCacheStore
    private let configManager: SettlementScannerConfigManager

    init(
        websiteScanner: SettlementWebsiteScanner = .shared,
        firebaseCatalogStore: FirebaseSettlementCatalogStore = .shared,
        cacheStore: SettlementCacheStore = .shared,
        configManager: SettlementScannerConfigManager = .shared
    ) {
        self.websiteScanner = websiteScanner
        self.firebaseCatalogStore = firebaseCatalogStore
        self.cacheStore = cacheStore
        self.configManager = configManager
    }

    func fetchSettlements(
        policy: SettlementRefreshPolicy = .preferFreshCache,
        progress: SettlementWebsiteScanner.ProgressHandler? = nil
    ) async -> SettlementFetchResult {
        let config = await configManager.configuration()
        let cached = cacheStore.load()

        print("[Owedly][DataSource] configured mode = \(config.catalogSourceMode.rawValue.uppercased()), deviceFallback = \(config.allowDeviceFallback)")

        if policy == .cacheOnly {
            if let cached {
                logLocalCache(cached)
                return SettlementFetchResult(settlements: cached.settlements, source: .localCache, warning: nil)
            }
            print("[Owedly][DataSource] LOCAL CACHE unavailable")
            return bundledFallback(warning: "No local settlement cache exists yet.")
        }

        if policy == .preferFreshCache,
           let cached,
           cacheStore.isFresh(cachedAt: cached.cachedAt, ttlHours: config.cacheTTLHours, schemaVersion: cached.schemaVersion) {
            if cacheMatchesConfiguredSource(cached.origin, mode: config.catalogSourceMode) {
                logLocalCache(cached)
                return SettlementFetchResult(settlements: cached.settlements, source: .localCache, warning: nil)
            } else {
                print("[Owedly][DataSource] fresh local cache belongs to another source; bypassing it to apply remote mode switch")
            }
        }

        switch config.catalogSourceMode {
        case .firebase:
            do {
                progress?(0.20)
                let firebase = try await firebaseCatalogStore.load(minimumExpectedItems: config.minimumExpectedItems)
                progress?(1.0)
                cacheStore.save(firebase.settlements, sourceURL: firebase.sourceURL, origin: .firebase)
                let updated = firebase.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                print("[Owedly][DataSource] FIREBASE ✅ loaded \(firebase.settlements.count) settlements; snapshot updatedAt = \(updated)")
                return SettlementFetchResult(
                    settlements: firebase.settlements,
                    source: .firebase,
                    warning: nil
                )
            } catch {
                print("[Owedly][DataSource] FIREBASE ❌ failed: \(error.localizedDescription)")

                if config.allowDeviceFallback {
                    print("[Owedly][DataSource] FALLBACK → DEVICE SCANNER")
                    return await fetchFromDeviceScanner(config: config, cached: cached, progress: progress, previousWarning: error.localizedDescription)
                }

                if let cached {
                    logLocalCache(cached, reason: "Firebase failed and device fallback is disabled")
                    return SettlementFetchResult(
                        settlements: cached.settlements,
                        source: .localCache,
                        warning: "Firebase catalog failed; using cached settlements. \(error.localizedDescription)"
                    )
                }
                return bundledFallback(warning: error.localizedDescription)
            }

        case .device:
            print("[Owedly][DataSource] DEVICE SCANNER selected by Firebase config (LIMITED: max \(config.maxPages) Open + \(config.upcomingMaxPages) Upcoming pages)")
            return await fetchFromDeviceScanner(config: config, cached: cached, progress: progress, previousWarning: nil)
        }
    }

    private func fetchFromDeviceScanner(
        config: SettlementScannerConfiguration,
        cached: (settlements: [Settlement], cachedAt: Date, sourceURL: URL, schemaVersion: Int, origin: SettlementCacheOrigin?)?,
        progress: SettlementWebsiteScanner.ProgressHandler?,
        previousWarning: String?
    ) async -> SettlementFetchResult {
        do {
            let website = try await websiteScanner.scan(configuration: config, progress: progress)
            cacheStore.save(website.settlements, sourceURL: website.sourceURL, origin: .deviceScanner)
            print("[Owedly][DataSource] DEVICE SCANNER ✅ parsed \(website.settlements.count) settlements from \(website.pagesScanned) page(s)")
            return SettlementFetchResult(
                settlements: website.settlements,
                source: .classActionWebsite,
                warning: previousWarning
            )
        } catch {
            print("[Owedly][DataSource] DEVICE SCANNER ❌ failed: \(error.localizedDescription)")

            // If the parser shape/URL appears to have changed, refresh only the tiny Firebase
            // config for the NEXT allowed daily attempt. Never run a second website crawl here.
            if shouldRefreshRemoteConfig(after: error) {
                _ = await configManager.configuration(forceRefresh: true)
            }

            if let cached {
                logLocalCache(cached, reason: "device scan failed")
                let prefix = previousWarning.map { "Firebase failed (\($0)); " } ?? ""
                return SettlementFetchResult(
                    settlements: cached.settlements,
                    source: .localCache,
                    warning: "\(prefix)live scan failed; using cached settlements. \(error.localizedDescription)"
                )
            }
            let combinedWarning = [previousWarning, error.localizedDescription]
                .compactMap { $0 }
                .joined(separator: " | ")
            return bundledFallback(warning: combinedWarning)
        }
    }

    private func cacheMatchesConfiguredSource(_ origin: SettlementCacheOrigin?, mode: SettlementCatalogSourceMode) -> Bool {
        switch (origin, mode) {
        case (.some(.firebase), .firebase), (.some(.deviceScanner), .device):
            return true
        default:
            return false
        }
    }

    private func logLocalCache(
        _ cached: (settlements: [Settlement], cachedAt: Date, sourceURL: URL, schemaVersion: Int, origin: SettlementCacheOrigin?),
        reason: String? = nil
    ) {
        let origin: String
        switch cached.origin {
        case .some(.firebase): origin = "FIREBASE"
        case .some(.deviceScanner): origin = "DEVICE SCANNER"
        case nil: origin = "LEGACY/UNKNOWN"
        }
        let age = Int(Date().timeIntervalSince(cached.cachedAt) / 60)
        let suffix = reason.map { "; reason = \($0)" } ?? ""
        print("[Owedly][DataSource] LOCAL CACHE ✅ \(cached.settlements.count) settlements; origin = \(origin); age = \(age)m\(suffix)")
    }

    private func shouldRefreshRemoteConfig(after error: Error) -> Bool {
        guard let scannerError = error as? SettlementWebsiteScannerError else { return false }
        switch scannerError {
        case .invalidResponse, .tooFewItems:
            return true
        case .disabled, .blockedOrChallenge, .throttled:
            return false
        }
    }

    private func bundledFallback(warning: String?) -> SettlementFetchResult {
        print("[Owedly][DataSource] BUNDLED FALLBACK ⚠️")
        return SettlementFetchResult(
            settlements: DemoSettlements.make(),
            source: .bundledFallback,
            warning: warning
        )
    }
}

// MARK: - Matching / scanner

struct SettlementMatch: Hashable {
    let settlement: Settlement
    let score: Int
    let reasons: [String]
}

struct SettlementScanResult {
    let allSettlements: [Settlement]
    let potentialMatches: [SettlementMatch]
    let source: SettlementDataSource
    let warning: String?
    let scannedAt: Date

    var nearestDeadline: Date? {
        potentialMatches
            .compactMap { $0.settlement.deadline }
            .filter { $0 > Date() }
            .min()
    }

    var nearestDeadlineDays: Int? {
        guard let nearestDeadline else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: nearestDeadline)
        return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }
}

final class SettlementScanner {
    static let shared = SettlementScanner()

    private(set) var latestResult: SettlementScanResult?

    func loadAndScan(
        dataManager: SettlementDataManager = .shared,
        profile: OnboardingDraft = OnboardingStore.shared.draft,
        refreshPolicy: SettlementRefreshPolicy = .preferFreshCache,
        progress: SettlementWebsiteScanner.ProgressHandler? = nil
    ) async -> SettlementScanResult {
        let fetch = await dataManager.fetchSettlements(policy: refreshPolicy, progress: progress)
        let result = scan(fetch.settlements, source: fetch.source, warning: fetch.warning, profile: profile)
        latestResult = result

        await MainActor.run {
            NotificationCenter.default.post(name: .owedlySettlementScanDidUpdate, object: nil)
        }
        await NotificationManager.shared.refreshIfAlreadyAuthorized(scanResult: result)
        return result
    }

    func scan(
        _ settlements: [Settlement],
        source: SettlementDataSource = .classActionWebsite,
        warning: String? = nil,
        profile: OnboardingDraft = OnboardingStore.shared.draft
    ) -> SettlementScanResult {
        let matches = settlements
            .filter { $0.status != .closed }
            .map { settlement -> SettlementMatch in
                let details = score(settlement, profile: profile)
                return SettlementMatch(settlement: settlement, score: details.score, reasons: details.reasons)
            }
            .filter { $0.score >= 4 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.settlement.isFeatured != $1.settlement.isFeatured {
                    return $0.settlement.isFeatured && !$1.settlement.isFeatured
                }
                if $0.settlement.sourceRank != $1.settlement.sourceRank {
                    return $0.settlement.sourceRank < $1.settlement.sourceRank
                }
                switch ($0.settlement.deadline, $1.settlement.deadline) {
                case let (lhs?, rhs?): return lhs < rhs
                case (.some, .none): return true
                default: return false
                }
            }

        return SettlementScanResult(
            allSettlements: settlements,
            potentialMatches: matches,
            source: source,
            warning: warning,
            scannedAt: Date()
        )
    }

    func score(_ settlement: Settlement, profile: OnboardingDraft) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []

        let normalizedCompany = settlement.company.normalizedForMatching
        let companyMatch = profile.selectedCompanies.contains {
            $0.rawValue.normalizedForMatching == normalizedCompany
        }
        if companyMatch {
            score += 5
            reasons.append("Company")
        }

        let selectedStates = Set(profile.selectedStates.map(\.normalizedForMatching))
        let settlementStates = Set(settlement.eligibleStates.map(\.normalizedForMatching))
        let stateMatch = !selectedStates.isEmpty && (settlement.isNationwide || !selectedStates.isDisjoint(with: settlementStates))
        if stateMatch {
            score += 4
            reasons.append(settlement.isNationwide ? "Nationwide" : "State")
        }

        let categoryMatch = profile.selectedCategories.contains {
            $0.normalizedForMatching == settlement.category.normalizedForMatching
        }
        if categoryMatch {
            score += 2
            reasons.append("Category")
        }

        if settlement.status == .open {
            score += 1
            reasons.append("Open")
        }

        return (score, reasons)
    }
}

private extension String {
    var normalizedForMatching: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private enum DemoSettlements {
    static func make(now: Date = Date()) -> [Settlement] {
        let calendar = Calendar.current
        func deadline(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: now) }
        let nationwide = ["CA", "California", "FL", "Florida", "NY", "New York", "TX", "Texas", "IL", "Illinois", "WA", "Washington", "OR", "Oregon"]

        return [
            Settlement(id: "demo-google", title: "Google Privacy Settlement", company: "Google", shortDescription: "Privacy-related settlement", category: "Privacy", payoutText: "Up to $100", deadline: deadline(12), proofRequired: false, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2020 — Now", status: .open),
            Settlement(id: "demo-att", title: "AT&T Data Incident Settlement", company: "AT&T", shortDescription: "Data breach settlement", category: "Data Breach", payoutText: "Varies", deadline: deadline(18), proofRequired: true, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2023 — 2024", status: .open),
            Settlement(id: "demo-amazon", title: "Amazon Subscription Settlement", company: "Amazon", shortDescription: "Subscription-related settlement", category: "Subscriptions", payoutText: "$25", deadline: deadline(31), proofRequired: false, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2020 — 2024", status: .open),
            Settlement(id: "demo-tiktok", title: "TikTok Privacy Settlement", company: "TikTok", shortDescription: "Privacy settlement", category: "Privacy", payoutText: "Varies", deadline: deadline(44), proofRequired: false, eligibleStates: nationwide, isNationwide: true, classPeriodText: "Before 2020 — Now", status: .open),
            Settlement(id: "demo-bofa", title: "Bank of America Fees Settlement", company: "Bank of America", shortDescription: "Banking settlement", category: "Banking", payoutText: "$50", deadline: deadline(56), proofRequired: true, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2020 — 2022", status: .open),
            Settlement(id: "demo-facebook", title: "Facebook Data Settlement", company: "Facebook", shortDescription: "Data privacy settlement", category: "Data Breach", payoutText: "Varies", deadline: deadline(67), proofRequired: false, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2020 — 2024", status: .open),
            Settlement(id: "demo-retail", title: "Retail Purchase Settlement", company: "Major Retailers", shortDescription: "Retail settlement", category: "Retail", payoutText: "$15", deadline: deadline(22), proofRequired: false, eligibleStates: nationwide, isNationwide: true, classPeriodText: "2025 — Now", status: .open)
        ]
    }
}
