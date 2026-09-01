import Foundation
import FirebaseDatabase
import SwiftSoup

// MARK: - Remote scanner configuration

enum SettlementCatalogSourceMode: String, Codable, Equatable {
    case firebase
    case device
}

struct SettlementScannerConfiguration: Codable, Equatable {
    var enabled: Bool
    var catalogSourceMode: SettlementCatalogSourceMode
    var allowDeviceFallback: Bool
    var settlementsURL: URL
    var headingSelector: String
    var headingRequiredText: String
    var maxPages: Int
    var upcomingEnabled: Bool
    var upcomingURL: URL
    var upcomingHeadingSelector: String
    var upcomingMaxPages: Int
    var upcomingLookbackDays: Int
    var cacheTTLHours: Double
    var configTTLHours: Double
    var requestTimeoutSeconds: Double
    var minimumExpectedItems: Int
    var allowDirectClassActionInRelease: Bool

    static let `default` = SettlementScannerConfiguration(
        enabled: true,
        catalogSourceMode: .firebase,
        allowDeviceFallback: true,
        settlementsURL: URL(string: "https://www.classaction.org/settlements")!,
        headingSelector: "h3",
        headingRequiredText: "Class Action Settlement",
        maxPages: 5,
        upcomingEnabled: true,
        upcomingURL: URL(string: "https://www.classaction.org/news/category/class-action-settlement")!,
        upcomingHeadingSelector: "h3",
        upcomingMaxPages: 3,
        upcomingLookbackDays: 75,
        cacheTTLHours: 24,
        configTTLHours: 1,
        requestTimeoutSeconds: 25,
        minimumExpectedItems: 20,
        allowDirectClassActionInRelease: false
    )
}

final class SettlementScannerConfigManager {
    static let shared = SettlementScannerConfigManager()

    private let dbProvider: () -> DatabaseReference?
    private let defaults: UserDefaults
    private let cachedConfigKey = "owedly.settlementScanner.config"
    private let cachedAtKey = "owedly.settlementScanner.config.cachedAt"

    init(
        dbProvider: @escaping () -> DatabaseReference? = {
            guard FirebaseBootstrap.isConfigured else { return nil }
            return Database.database().reference()
        },
        defaults: UserDefaults = .standard
    ) {
        self.dbProvider = dbProvider
        self.defaults = defaults
    }

    func configuration(forceRefresh: Bool = false) async -> SettlementScannerConfiguration {
        let cached = cachedConfiguration()
        if !forceRefresh,
           let cached,
           let cachedAt = defaults.object(forKey: cachedAtKey) as? Date {
            #if DEBUG
            // Keep the Firebase/device source switch quick to test from Xcode without reinstalling.
            let effectiveTTL = min(cached.configTTLHours * 3600, 15)
            #else
            let effectiveTTL = cached.configTTLHours * 3600
            #endif
            if Date().timeIntervalSince(cachedAt) < effectiveTTL {
                return cached
            }
        }

        guard let root = dbProvider() else {
            return cached ?? .default
        }

        do {
            let snapshot = try await root
                .child("appConfig")
                .child("settlementScanner")
                .getData()

            guard let data = snapshot.value as? [String: Any] else {
                return cached ?? .default
            }

            let config = parse(data: data, fallback: cached ?? .default)
            cache(config)
            return config
        } catch {
            print("[SettlementScannerConfig] Realtime Database config failed: \(error)")
            return cached ?? .default
        }
    }

    private func parse(data: [String: Any], fallback: SettlementScannerConfiguration) -> SettlementScannerConfiguration {
        var result = fallback

        if let value = data["enabled"] as? Bool { result.enabled = value }
        if let useFirebase = data["useFirebaseCatalog"] as? Bool {
            result.catalogSourceMode = useFirebase ? .firebase : .device
        } else if let raw = data["catalogSourceMode"] as? String,
                  let mode = SettlementCatalogSourceMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            result.catalogSourceMode = mode
        }
        if let value = data["allowDeviceFallback"] as? Bool { result.allowDeviceFallback = value }
        if let raw = data["settlementsURL"] as? String, let url = URL(string: raw) { result.settlementsURL = url }
        if let value = data["headingSelector"] as? String, !value.isEmpty { result.headingSelector = value }
        if let value = data["headingRequiredText"] as? String, !value.isEmpty { result.headingRequiredText = value }
        if let value = (data["maxPages"] as? NSNumber)?.intValue { result.maxPages = max(1, min(value, 5)) }
        if let value = data["upcomingEnabled"] as? Bool { result.upcomingEnabled = value }
        if let raw = data["upcomingURL"] as? String, let url = URL(string: raw) { result.upcomingURL = url }
        if let value = data["upcomingHeadingSelector"] as? String, !value.isEmpty { result.upcomingHeadingSelector = value }
        if let value = (data["upcomingMaxPages"] as? NSNumber)?.intValue { result.upcomingMaxPages = max(1, min(value, 3)) }
        if let value = (data["upcomingLookbackDays"] as? NSNumber)?.intValue { result.upcomingLookbackDays = max(7, min(value, 365)) }
        if let value = (data["cacheTTLHours"] as? NSNumber)?.doubleValue {
            // Safety floor: production builds never refresh the source catalog more than once
            // per 24 hours, even if the remote value is accidentally configured lower.
            result.cacheTTLHours = max(24, min(value, 168))
        }
        if data["configTTLHours"] != nil {
            // Keep emergency scanner controls responsive regardless of a stale/incorrect remote TTL.
            result.configTTLHours = 1
        }
        if let value = (data["requestTimeoutSeconds"] as? NSNumber)?.doubleValue { result.requestTimeoutSeconds = max(5, min(value, 60)) }
        if let value = (data["minimumExpectedItems"] as? NSNumber)?.intValue { result.minimumExpectedItems = max(1, min(value, 5000)) }
        if let value = data["allowDirectClassActionInRelease"] as? Bool { result.allowDirectClassActionInRelease = value }

        return result
    }

    private func cachedConfiguration() -> SettlementScannerConfiguration? {
        guard let data = defaults.data(forKey: cachedConfigKey),
              var config = try? JSONDecoder().decode(SettlementScannerConfiguration.self, from: data) else {
            return nil
        }

        // Normalize values persisted by older app builds before they can be used. This makes the
        // 24h catalog floor and 1h emergency-config refresh effective immediately after update.
        config.cacheTTLHours = max(24, min(config.cacheTTLHours, 168))
        config.configTTLHours = 1
        // Hard safety caps for on-device scanning. Remote config can reduce these values,
        // but can never turn the iPhone fallback into a full-site crawler.
        config.maxPages = max(1, min(config.maxPages, 5))
        config.upcomingMaxPages = max(1, min(config.upcomingMaxPages, 3))
        return config
    }

    private func cache(_ config: SettlementScannerConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: cachedConfigKey)
            defaults.set(Date(), forKey: cachedAtKey)
        }
    }
}

// MARK: - Firebase catalog snapshot

enum FirebaseSettlementCatalogError: LocalizedError {
    case unavailable
    case invalidPayload
    case tooFewItems(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The Firebase settlement catalog is unavailable."
        case .invalidPayload:
            return "The Firebase settlement catalog has an invalid format."
        case .tooFewItems(let count):
            return "The Firebase settlement catalog contains only \(count) items."
        }
    }
}

private struct FirebaseSettlementCatalogPayload: Decodable {
    let schemaVersion: Int
    let updatedAt: Date?
    let sourceURL: URL
    let count: Int?
    let settlements: [Settlement]
}

struct FirebaseSettlementCatalogResult {
    let settlements: [Settlement]
    let sourceURL: URL
    let updatedAt: Date?
    let schemaVersion: Int
}

final class FirebaseSettlementCatalogStore {
    static let shared = FirebaseSettlementCatalogStore()

    private let dbProvider: () -> DatabaseReference?

    init(dbProvider: @escaping () -> DatabaseReference? = {
        guard FirebaseBootstrap.isConfigured else { return nil }
        return Database.database().reference()
    }) {
        self.dbProvider = dbProvider
    }

    func load(minimumExpectedItems: Int) async throws -> FirebaseSettlementCatalogResult {
        guard let root = dbProvider() else {
            throw FirebaseSettlementCatalogError.unavailable
        }

        let snapshot = try await root
            .child("settlementCatalog")
            .child("current")
            .getData()

        guard snapshot.exists(), let value = snapshot.value else {
            throw FirebaseSettlementCatalogError.unavailable
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            throw FirebaseSettlementCatalogError.invalidPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: raw) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(raw)"
            )
        }

        let payload: FirebaseSettlementCatalogPayload
        do {
            payload = try decoder.decode(FirebaseSettlementCatalogPayload.self, from: data)
        } catch {
            print("[Owedly][FirebaseCatalog] decode failed: \(error)")
            throw FirebaseSettlementCatalogError.invalidPayload
        }

        guard payload.schemaVersion >= 1, !payload.settlements.isEmpty else {
            throw FirebaseSettlementCatalogError.invalidPayload
        }

        let minimum = max(1, minimumExpectedItems)
        guard payload.settlements.count >= minimum else {
            throw FirebaseSettlementCatalogError.tooFewItems(payload.settlements.count)
        }

        if let declaredCount = payload.count, declaredCount != payload.settlements.count {
            print("[Owedly][FirebaseCatalog] warning: count=\(declaredCount), decoded=\(payload.settlements.count)")
        }

        return FirebaseSettlementCatalogResult(
            settlements: payload.settlements,
            sourceURL: payload.sourceURL,
            updatedAt: payload.updatedAt,
            schemaVersion: payload.schemaVersion
        )
    }
}

// MARK: - Local catalog cache

enum SettlementCacheOrigin: String, Codable, Equatable {
    case firebase
    case deviceScanner
}

private struct SettlementCachePayload: Codable {
    let schemaVersion: Int
    let cachedAt: Date
    let sourceURL: URL
    let origin: SettlementCacheOrigin?
    let settlements: [Settlement]
}

final class SettlementCacheStore {
    static let shared = SettlementCacheStore()

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> (settlements: [Settlement], cachedAt: Date, sourceURL: URL, schemaVersion: Int, origin: SettlementCacheOrigin?)? {
        guard let url = try? cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(SettlementCachePayload.self, from: data),
              payload.schemaVersion >= 1,
              !payload.settlements.isEmpty else {
            return nil
        }
        return (payload.settlements, payload.cachedAt, payload.sourceURL, payload.schemaVersion, payload.origin)
    }

    func save(_ settlements: [Settlement], sourceURL: URL, origin: SettlementCacheOrigin) {
        guard !settlements.isEmpty,
              let url = try? cacheFileURL() else { return }

        let payload = SettlementCachePayload(
            schemaVersion: 4,
            cachedAt: Date(),
            sourceURL: sourceURL,
            origin: origin,
            settlements: settlements
        )

        do {
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[SettlementCache] save failed: \(error)")
        }
    }

    func isFresh(cachedAt: Date, ttlHours: Double, schemaVersion: Int) -> Bool {
        // v3 refreshes the richer Upcoming parsing/image extraction. Older caches are
        // intentionally treated as stale once after updating the app.
        guard schemaVersion >= 4, ttlHours > 0 else { return false }
        return Date().timeIntervalSince(cachedAt) < ttlHours * 3600
    }

    private func cacheFileURL() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Owedly", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("settlements-cache-v1.json")
    }
}

// MARK: - Website scan

enum SettlementWebsiteScannerError: LocalizedError {
    case disabled
    case invalidResponse
    case blockedOrChallenge
    case throttled
    case tooFewItems(Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Direct settlement scanning is disabled by remote configuration."
        case .invalidResponse:
            return "The settlement source returned an invalid response."
        case .blockedOrChallenge:
            return "The settlement source returned a challenge, access-denied, or rate-limit response."
        case .throttled:
            return "The settlement source was already checked within the daily refresh window."
        case .tooFewItems(let count):
            return "The settlement page parsed only \(count) items, so the response was not cached."
        }
    }
}

/// Coalesces every live website refresh into one shared task. Multiple callers (cold launch,
/// Discover, foreground refresh) all await the same request sequence instead of starting
/// parallel crawls. The gate resets after success or failure so a future stale refresh can run.
private actor SettlementWebsiteScanGate {
    private var inFlightTask: Task<SettlementWebsiteScanResult, Error>?
    private let defaults: UserDefaults
    private let lastAttemptKey = "owedly.settlementScanner.lastLiveAttemptAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func run(
        minimumAttemptInterval: TimeInterval,
        operation: @escaping () async throws -> SettlementWebsiteScanResult
    ) async throws -> SettlementWebsiteScanResult {
        if let inFlightTask {
            return try await inFlightTask.value
        }

        // Throttle attempts, not only successful cache writes. A failed/challenged request must
        // not cause every subsequent foreground to hit the source again while the cache is stale.
        if let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date,
           Date().timeIntervalSince(lastAttempt) < minimumAttemptInterval {
            throw SettlementWebsiteScannerError.throttled
        }

        defaults.set(Date(), forKey: lastAttemptKey)
        let task = Task {
            try await operation()
        }
        inFlightTask = task
        defer { inFlightTask = nil }
        return try await task.value
    }
}

struct SettlementWebsiteScanResult {
    let settlements: [Settlement]
    let pagesScanned: Int
    let sourceURL: URL
}

final class SettlementWebsiteScanner {
    static let shared = SettlementWebsiteScanner()

    typealias ProgressHandler = (Double) -> Void

    private let session: URLSession
    private let scanGate = SettlementWebsiteScanGate()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForResource = 35
            configuration.httpMaximumConnectionsPerHost = 2
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func scan(
        configuration: SettlementScannerConfiguration,
        progress: ProgressHandler? = nil
    ) async throws -> SettlementWebsiteScanResult {
        guard configuration.enabled else { throw SettlementWebsiteScannerError.disabled }

        #if !DEBUG
        // Emergency release kill switch from Realtime Database. Debug builds stay usable for
        // development even when production direct scanning has been turned off remotely.
        guard configuration.allowDirectClassActionInRelease else {
            throw SettlementWebsiteScannerError.disabled
        }
        #endif

        return try await scanGate.run(
            minimumAttemptInterval: max(24, configuration.cacheTTLHours) * 3600
        ) { [self] in
            try await performScan(configuration: configuration, progress: progress)
        }
    }

    private func performScan(
        configuration: SettlementScannerConfiguration,
        progress: ProgressHandler?
    ) async throws -> SettlementWebsiteScanResult {
        let scanStartedAt = Date()
        var nextURL: URL? = configuration.settlementsURL
        var visited = Set<URL>()
        var collectedOpen: [Settlement] = []
        var openPagesScanned = 0
        var rank = 0

        // Primary source: settlements whose claim flow is already live/open.
        while let pageURL = nextURL,
              openPagesScanned < configuration.maxPages,
              !visited.contains(pageURL) {
            visited.insert(pageURL)
            let pageStartedAt = Date()
            progress?(min(0.08 + Double(openPagesScanned) * 0.10, 0.48))

            let html = try await downloadHTML(from: pageURL, timeout: configuration.requestTimeoutSeconds)
            progress?(min(0.28 + Double(openPagesScanned) * 0.10, 0.58))
            let page = try parsePage(
                html: html,
                pageURL: pageURL,
                configuration: configuration,
                startingRank: rank
            )
            collectedOpen.append(contentsOf: page.settlements)
            rank += page.settlements.count
            openPagesScanned += 1
            progress?(min(0.48 + Double(openPagesScanned) * 0.04, 0.68))
            print(
                "[SettlementWebsite] open page \(openPagesScanned): \(page.settlements.count) items in " +
                String(format: "%.2fs", Date().timeIntervalSince(pageStartedAt))
            )

            if let candidate = page.nextPageURL,
               candidate.host?.lowercased() == configuration.settlementsURL.host?.lowercased(),
               candidate.path.hasPrefix(configuration.settlementsURL.path),
               !visited.contains(candidate) {
                nextURL = candidate
            } else {
                nextURL = nil
            }
        }

        let openSettlements = deduplicateAndSort(collectedOpen)
        guard openSettlements.count >= configuration.minimumExpectedItems else {
            throw SettlementWebsiteScannerError.tooFewItems(openSettlements.count)
        }

        progress?(0.70)
        var upcomingSettlements: [Settlement] = []
        var upcomingPagesScanned = 0

        // Secondary source: recently announced settlements that are not yet present in the
        // live claim catalog. Failure here is intentionally non-fatal: open settlements are
        // still useful and should remain cacheable.
        if configuration.upcomingEnabled {
            do {
                let result = try await scanUpcoming(
                    configuration: configuration,
                    openSettlements: openSettlements,
                    progress: progress
                )
                upcomingSettlements = result.settlements
                upcomingPagesScanned = result.pagesScanned
            } catch {
                print("[SettlementWebsite] upcoming scan failed (open catalog preserved): \(error)")
            }
        }

        let combined = deduplicateAndSort(openSettlements + upcomingSettlements)
        progress?(1.0)
        print(
            "[SettlementWebsite] full scan: \(openSettlements.count) open + \(upcomingSettlements.count) upcoming = " +
            "\(combined.count) unique items / \(openPagesScanned + upcomingPagesScanned) page(s) in " +
            String(format: "%.2fs", Date().timeIntervalSince(scanStartedAt))
        )
        return SettlementWebsiteScanResult(
            settlements: combined,
            pagesScanned: openPagesScanned + upcomingPagesScanned,
            sourceURL: configuration.settlementsURL
        )
    }

    private func downloadHTML(from url: URL, timeout: Double) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(
            "Owedly-iOS/1.0 (settlement catalog freshness check)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SettlementWebsiteScannerError.invalidResponse
        }
        if [401, 403, 429].contains(http.statusCode) {
            throw SettlementWebsiteScannerError.blockedOrChallenge
        }
        guard (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SettlementWebsiteScannerError.invalidResponse
        }

        let lowered = html.lowercased()
        if lowered.contains("cf-chl-") ||
            lowered.contains("captcha") ||
            lowered.contains("access denied") ||
            lowered.contains("verify you are human") {
            throw SettlementWebsiteScannerError.blockedOrChallenge
        }
        return html
    }

    private struct UpcomingScanResult {
        let settlements: [Settlement]
        let pagesScanned: Int
    }

    private struct ParsedUpcomingPage {
        let settlements: [Settlement]
        let nextPageURL: URL?
        let oldestPublishedAt: Date?
    }

    private func scanUpcoming(
        configuration: SettlementScannerConfiguration,
        openSettlements: [Settlement],
        progress: ProgressHandler?
    ) async throws -> UpcomingScanResult {
        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day,
            value: -configuration.upcomingLookbackDays,
            to: calendar.startOfDay(for: Date())
        ) ?? .distantPast

        var nextURL: URL? = configuration.upcomingURL
        var visited = Set<URL>()
        var collected: [Settlement] = []
        var pagesScanned = 0
        var rank = 100_000

        while let pageURL = nextURL,
              pagesScanned < configuration.upcomingMaxPages,
              !visited.contains(pageURL) {
            visited.insert(pageURL)
            let pageStartedAt = Date()
            progress?(min(0.72 + Double(pagesScanned) * 0.07, 0.91))

            let html = try await downloadHTML(from: pageURL, timeout: configuration.requestTimeoutSeconds)
            let page = try parseUpcomingPage(
                html: html,
                pageURL: pageURL,
                configuration: configuration,
                startingRank: rank,
                cutoff: cutoff
            )
            collected.append(contentsOf: page.settlements)
            rank += page.settlements.count
            pagesScanned += 1
            progress?(min(0.80 + Double(pagesScanned) * 0.06, 0.97))

            print(
                "[SettlementWebsite] upcoming page \(pagesScanned): \(page.settlements.count) candidates in " +
                String(format: "%.2fs", Date().timeIntervalSince(pageStartedAt))
            )

            // The news feed is newest-first. Once the oldest item on a page has crossed the
            // lookback boundary there is no reason to keep paging into older announcements.
            if let oldest = page.oldestPublishedAt, oldest < cutoff {
                nextURL = nil
            } else if let candidate = page.nextPageURL,
                      candidate.host?.lowercased() == configuration.upcomingURL.host?.lowercased(),
                      candidate.path.hasPrefix(configuration.upcomingURL.path),
                      !visited.contains(candidate) {
                nextURL = candidate
            } else {
                nextURL = nil
            }
        }

        let candidates = deduplicateAndSort(collected)
        let uniqueUpcoming = candidates.filter { candidate in
            !openSettlements.contains(where: { isLikelySameSettlement(candidate, $0) })
        }

        print(
            "[SettlementWebsite] upcoming: \(candidates.count) recent announcement(s), " +
            "\(uniqueUpcoming.count) not already present in the open catalog"
        )
        return UpcomingScanResult(settlements: uniqueUpcoming, pagesScanned: pagesScanned)
    }

    private func parseUpcomingPage(
        html: String,
        pageURL: URL,
        configuration: SettlementScannerConfiguration,
        startingRank: Int,
        cutoff: Date
    ) throws -> ParsedUpcomingPage {
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let headings = try document.select(configuration.upcomingHeadingSelector)
        var settlements: [Settlement] = []
        var publishedDates: [Date] = []
        var rank = startingRank

        for heading in headings {
            let title = try heading.text().trimmedAndCollapsed
            guard title.localizedCaseInsensitiveContains("settlement"),
                  !title.localizedCaseInsensitiveContains("[dismissed]") else { continue }
            guard let articleURL = try firstNewsArticleURL(in: heading, baseURL: pageURL),
                  let container = try nearestUpcomingContainer(from: heading) else { continue }

            let fullText = try container.text().trimmedAndCollapsed
            guard fullText.range(of: "by ", options: [.caseInsensitive]) != nil else { continue }

            let publishedAt = parsePublishedDate(from: fullText)
            if let publishedAt {
                publishedDates.append(publishedAt)
                guard publishedAt >= cutoff else { continue }
            }

            if let settlement = try makeUpcomingSettlement(
                title: title,
                articleURL: articleURL,
                container: container,
                pageURL: pageURL,
                publishedAt: publishedAt,
                sourceRank: rank
            ) {
                settlements.append(settlement)
                rank += 1
            }
        }

        return ParsedUpcomingPage(
            settlements: settlements,
            nextPageURL: try discoverNextPageURL(in: document, currentURL: pageURL),
            oldestPublishedAt: publishedDates.min()
        )
    }

    private func nearestUpcomingContainer(from heading: Element) throws -> Element? {
        var current: Element? = heading
        for _ in 0..<9 {
            guard let parent = current?.parent() else { break }
            let text = try parent.text().trimmedAndCollapsed
            let childHeadings = try parent.select("h3")
            if childHeadings.count == 1,
               text.range(of: "by ", options: [.caseInsensitive]) != nil,
               text.count < 1_600 {
                return parent
            }
            current = parent
        }
        return heading.parent()
    }

    private func makeUpcomingSettlement(
        title: String,
        articleURL: URL,
        container: Element,
        pageURL: URL,
        publishedAt: Date?,
        sourceRank: Int
    ) throws -> Settlement? {
        guard !title.isEmpty else { return nil }
        let description = try extractUpcomingSummary(from: container, title: title)
        let combinedText = (title + " " + description).trimmedAndCollapsed
        let company = inferCompany(title: title, description: description)
        let category = inferCategory(title: title, description: description)
        let states = inferStates(from: combinedText)
        let isNationwide = inferNationwide(from: combinedText)
        let imageURL = try firstNearbyImageURL(from: container, baseURL: pageURL)
        let id = stableSettlementID(title: title, stableKey: articleURL.absoluteString)

        return Settlement(
            id: id,
            title: title,
            company: company,
            shortDescription: description,
            eligibilityDescription: description.isEmpty ? nil : description,
            category: category,
            payoutText: nil,
            deadline: nil,
            proofRequired: nil,
            eligibleStates: states,
            isNationwide: isNationwide,
            classPeriodText: nil,
            officialClaimURL: nil,
            sourceURL: articleURL,
            imageURL: imageURL,
            status: .upcoming,
            createdAt: publishedAt,
            updatedAt: publishedAt ?? Date(),
            isFeatured: false,
            sourceRank: sourceRank
        )
    }

    private func firstNewsArticleURL(in element: Element, baseURL: URL) throws -> URL? {
        let links = try element.select("a[href]")
        for link in links {
            let raw = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty,
                  let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                  resolved.host?.lowercased().contains("classaction.org") == true,
                  resolved.path.hasPrefix("/news/") else { continue }
            return resolved
        }

        if let parent = element.parent() {
            let links = try parent.select("a[href]")
            for link in links {
                let raw = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty,
                      let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                      resolved.host?.lowercased().contains("classaction.org") == true,
                      resolved.path.hasPrefix("/news/") else { continue }
                return resolved
            }
        }
        return nil
    }

    private func extractUpcomingSummary(from container: Element, title: String) throws -> String {
        let paragraphs = try container.select("p")
        var candidates: [String] = []
        for paragraph in paragraphs {
            let text = try paragraph.text().trimmedAndCollapsed
            guard text.count >= 24,
                  text.localizedCaseInsensitiveCompare(title) != .orderedSame,
                  !text.lowercased().hasPrefix("by ") else { continue }
            candidates.append(text)
        }
        if let best = candidates.max(by: { $0.count < $1.count }) {
            return best
        }

        var fallback = try container.text().trimmedAndCollapsed
        if let titleRange = fallback.range(of: title, options: [.caseInsensitive]) {
            fallback.removeSubrange(titleRange)
        }
        fallback = fallback.replacingOccurrences(
            of: #"(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}"#,
            with: "",
            options: .regularExpression
        ).trimmedAndCollapsed
        if let byRange = fallback.range(of: #"\s+by\s+[^|]+$"#, options: [.regularExpression, .caseInsensitive]) {
            fallback = String(fallback[..<byRange.lowerBound]).trimmedAndCollapsed
        }
        return fallback
    }

    private func parsePublishedDate(from text: String) -> Date? {
        let pattern = #"(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}"#
        guard let raw = capture(in: text, pattern: pattern, group: 0) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.date(from: raw)
    }

    private func isLikelySameSettlement(_ lhs: Settlement, _ rhs: Settlement) -> Bool {
        let lhsTitle = normalizedIdentityText(lhs.title)
        let rhsTitle = normalizedIdentityText(rhs.title)
        if lhsTitle == rhsTitle { return true }

        let lhsCompany = normalizedIdentityText(lhs.company)
        let rhsCompany = normalizedIdentityText(rhs.company)
        let sameCompany = !lhsCompany.isEmpty && lhsCompany == rhsCompany

        let lhsTokens = identityTokens(lhs.title)
        let rhsTokens = identityTokens(rhs.title)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        let jaccard = union == 0 ? 0 : Double(overlap) / Double(union)

        if sameCompany && overlap >= 2 && jaccard >= 0.22 { return true }
        if overlap >= 4 && jaccard >= 0.42 { return true }
        return false
    }

    private func identityTokens(_ value: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "class", "action", "settlement", "settlements", "lawsuit", "lawsuits",
            "case", "cases", "ends", "end", "resolves", "resolve", "resolved", "wraps", "up", "over",
            "alleged", "allegedly", "claims", "claim", "against", "the", "to", "of", "for", "in", "on",
            "million", "billion", "thousand", "update"
        ]
        return Set(
            normalizedIdentityText(value)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 2 && !stopWords.contains($0) && !$0.allSatisfy { character in character.isNumber } }
        )
    }

    private func normalizedIdentityText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: #"\$?[0-9]+(?:[.,][0-9]+)*[kmb]?\+?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmedAndCollapsed
    }

    private struct ParsedPage {
        let settlements: [Settlement]
        let nextPageURL: URL?
    }

    private func parsePage(
        html: String,
        pageURL: URL,
        configuration: SettlementScannerConfiguration,
        startingRank: Int
    ) throws -> ParsedPage {
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let headings = try document.select(configuration.headingSelector)
        var settlements: [Settlement] = []
        var rank = startingRank

        for heading in headings {
            let rawTitle = try heading.text().trimmedAndCollapsed
            guard rawTitle.localizedCaseInsensitiveContains(configuration.headingRequiredText) else { continue }
            guard let container = try nearestSettlementContainer(from: heading, requiredText: configuration.headingRequiredText) else { continue }
            if let settlement = try makeSettlement(from: heading, container: container, pageURL: pageURL, sourceRank: rank) {
                settlements.append(settlement)
                rank += 1
            }
        }

        return ParsedPage(
            settlements: settlements,
            nextPageURL: try discoverNextPageURL(in: document, currentURL: pageURL)
        )
    }

    private func nearestSettlementContainer(from heading: Element, requiredText: String) throws -> Element? {
        var current: Element? = heading
        for _ in 0..<10 {
            guard let parent = current?.parent() else { break }
            let text = try parent.text()
            if text.localizedCaseInsensitiveContains("Payout"),
               text.localizedCaseInsensitiveContains("Deadline"),
               text.localizedCaseInsensitiveContains("Required?") {
                let childHeadings = try parent.select("h3")
                var matchingHeadingCount = 0
                for childHeading in childHeadings {
                    if try childHeading.text().localizedCaseInsensitiveContains(requiredText) {
                        matchingHeadingCount += 1
                    }
                }
                if matchingHeadingCount == 1 { return parent }
            }
            current = parent
        }
        return heading.parent()
    }

    private func makeSettlement(
        from heading: Element,
        container: Element,
        pageURL: URL,
        sourceRank: Int
    ) throws -> Settlement? {
        let title = try heading.text().trimmedAndCollapsed
        guard !title.isEmpty else { return nil }

        let fullText = try container.text().trimmedAndCollapsed
        guard fullText.localizedCaseInsensitiveContains("Payout"),
              fullText.localizedCaseInsensitiveContains("Deadline") else { return nil }

        let officialURL = try firstURL(in: heading, baseURL: pageURL)
            ?? firstOfficialURL(in: container, baseURL: pageURL)
        let imageURL = try firstNearbyImageURL(from: container, baseURL: pageURL)
        let payout = capture(in: fullText, pattern: #"Payout\s+(.+?)\s+Deadline"#, group: 1)?.trimmedAndCollapsed
        let deadlineRaw = capture(in: fullText, pattern: #"Deadline\s+([0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}|Varies)"#, group: 1)
        let proofRaw = capture(in: fullText, pattern: #"Required\?\s*(Yes|No|N/?A)"#, group: 1)
        let deadline = parseDeadline(deadlineRaw)
        let proofRequired: Bool?
        switch proofRaw?.lowercased() {
        case "yes": proofRequired = true
        case "no": proofRequired = false
        default: proofRequired = nil
        }

        let description = extractDescription(from: fullText, proofRaw: proofRaw)
        let company = inferCompany(title: title, description: description)
        let category = inferCategory(title: title, description: description)
        // Infer geography from the eligibility copy, not the title. This avoids false positives
        // such as the “Washington Nationals” team name being treated as Washington State.
        let states = inferStates(from: description)
        let isNationwide = inferNationwide(from: description)
        let isFeatured = fullText.localizedCaseInsensitiveContains("Featured")
        let status: Settlement.Status
        if let deadline, deadline < Calendar.current.startOfDay(for: Date()) {
            status = .closed
        } else {
            status = .open
        }

        let stableKey = officialURL?.absoluteString ?? title
        let id = stableSettlementID(title: title, stableKey: stableKey)

        return Settlement(
            id: id,
            title: title,
            company: company,
            shortDescription: description,
            eligibilityDescription: description.isEmpty ? nil : description,
            category: category,
            payoutText: payout,
            deadline: deadline,
            proofRequired: proofRequired,
            eligibleStates: states,
            isNationwide: isNationwide,
            classPeriodText: nil,
            officialClaimURL: officialURL,
            sourceURL: pageURL,
            imageURL: imageURL,
            status: status,
            createdAt: nil,
            updatedAt: Date(),
            isFeatured: isFeatured,
            sourceRank: sourceRank
        )
    }

    private func discoverNextPageURL(in document: Document, currentURL: URL) throws -> URL? {
        let links = try document.select("a[href]")
        for link in links {
            let rel = try link.attr("rel").lowercased()
            let text = try link.text().trimmedAndCollapsed.lowercased()
            let ariaLabel = try link.attr("aria-label").lowercased()
            let looksLikeNext = rel == "next" ||
                text == "next" || text == "next →" || text == "next >" ||
                ariaLabel.contains("next")
            guard looksLikeNext else { continue }
            let raw = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.hasPrefix("#"), !raw.lowercased().hasPrefix("javascript:") else { continue }
            guard let resolved = URL(string: raw, relativeTo: currentURL)?.absoluteURL else { continue }

            var candidateComponents = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
            candidateComponents?.fragment = nil
            var currentComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
            currentComponents?.fragment = nil
            guard let candidate = candidateComponents?.url,
                  candidate != currentComponents?.url else { continue }
            return candidate
        }
        return nil
    }

    private func firstURL(in element: Element, baseURL: URL) throws -> URL? {
        guard let link = try element.select("a[href]").first() else { return nil }
        let raw = try link.attr("href")
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private func firstOfficialURL(in element: Element, baseURL: URL) throws -> URL? {
        let links = try element.select("a[href]")
        for link in links {
            let text = try link.text().lowercased()
            guard text.contains("official settlement") else { continue }
            let raw = try link.attr("href")
            return URL(string: raw, relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }

    private func firstNearbyImageURL(from element: Element, baseURL: URL) throws -> URL? {
        var current: Element? = element
        for _ in 0..<4 {
            if let current, let url = try firstImageURL(in: current, baseURL: baseURL) {
                return url
            }
            current = current?.parent()
        }
        return nil
    }

    private func firstImageURL(in element: Element, baseURL: URL) throws -> URL? {
        let images = try element.select("img")
        for image in images {
            let attributes = ["src", "data-src", "data-lazy-src", "data-original"]
            for attribute in attributes {
                let raw = try image.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = usableImageURL(raw, baseURL: baseURL) { return url }
            }

            let srcSets = ["srcset", "data-srcset"]
            for attribute in srcSets {
                let raw = try image.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
                let candidates = raw.split(separator: ",").map { part -> String in
                    part.trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: " ").first.map(String.init) ?? ""
                }
                for candidate in candidates.reversed() {
                    if let url = usableImageURL(candidate, baseURL: baseURL) { return url }
                }
            }
        }
        return nil
    }

    private func usableImageURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().contains("placeholder") else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private func extractDescription(from fullText: String, proofRaw: String?) -> String {
        guard let proofRaw else { return "" }
        guard let requiredRange = fullText.range(of: "Required?", options: [.caseInsensitive]),
              let proofRange = fullText.range(of: proofRaw, options: [.caseInsensitive], range: requiredRange.upperBound..<fullText.endIndex) else {
            return ""
        }

        var tail = String(fullText[proofRange.upperBound...]).trimmedAndCollapsed
        if let visitRange = tail.range(of: "Visit Official Settlement Website", options: [.caseInsensitive]) {
            tail = String(tail[..<visitRange.lowerBound]).trimmedAndCollapsed
        }
        return tail
    }

    private func parseDeadline(_ raw: String?) -> Date? {
        guard let raw, raw.lowercased() != "varies" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = raw.split(separator: "/").last?.count == 4 ? "M/d/yyyy" : "M/d/yy"
        guard let date = formatter.date(from: raw) else { return nil }
        var components = formatter.calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 23
        components.minute = 59
        return formatter.calendar.date(from: components)
    }

    private func inferCompany(title: String, description: String) -> String {
        let haystack = (" " + title + " " + description + " ").lowercased()
        let aliases: [(needles: [String], company: String)] = [
            (["youtube", " google "], "Google"),
            ([" amazon "], "Amazon"),
            (["at&t"], "AT&T"),
            (["tiktok"], "TikTok"),
            (["bank of america"], "Bank of America"),
            (["facebook", "meta platforms", " meta "], "Facebook")
        ]
        for alias in aliases where alias.needles.contains(where: { haystack.contains($0) }) {
            return alias.company
        }

        // Open-settlement cards usually use “Company - Subject Class Action Settlement”.
        var cleaned = title.trimmedAndCollapsed
        if let separator = cleaned.range(of: " - ") {
            return String(cleaned[..<separator.lowerBound]).trimmedAndCollapsed
        }

        // News headlines are commonly “$3.6M+ Company Settlement Ends …”. Strip the amount
        // and generic prefix so the same company can participate in onboarding prioritization.
        cleaned = cleaned.replacingOccurrences(
            of: #"^(?:Up\s+to\s+)?\$[0-9.,]+\s*[KMBkmb]?\+?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmedAndCollapsed

        let settlementMarkers = [" Class Action Settlement", " Settlement", " Settlements"]
        for marker in settlementMarkers {
            if let range = cleaned.range(of: marker, options: [.caseInsensitive]), range.lowerBound > cleaned.startIndex {
                let candidate = String(cleaned[..<range.lowerBound]).trimmedAndCollapsed
                if !candidate.isEmpty { return candidate }
            }
        }

        return cleaned
            .replacingOccurrences(of: "Class Action Settlement", with: "", options: [.caseInsensitive])
            .trimmedAndCollapsed
    }

    private func inferCategory(title: String, description: String) -> String {
        let text = (title + " " + description).lowercased()

        // Prefer the most specific/high-signal categories first. The website cards do not expose
        // a stable category field, so this is deliberately conservative and uses user-facing
        // labels from SettlementCategoryCatalog.
        if text.contains("data breach") || text.contains("cyberattack") || text.contains("cyber incident") || text.contains("ransomware") { return "Data Breach" }
        if text.contains("privacy") || text.contains("tracking pixel") || text.contains("tracking pixels") || text.contains("biometric") || text.contains("personal data") { return "Privacy" }
        if text.contains("pfas") || text.contains("forever chemical") { return "PFAS" }
        if text.contains("recall") { return "Product Recall" }
        if text.contains("defect") || text.contains("defective") || text.contains("fails to") { return "Defective Product" }
        if text.contains("antitrust") || text.contains("price fixing") || text.contains("price-fixing") || text.contains("monopol") { return "Antitrust" }
        if text.contains("false advertising") || text.contains("misleading") || text.contains("deceptive advertising") || text.contains("fake discount") { return "False Advertising" }
        if text.contains("fraud") || text.contains("scam") { return "Fraud" }
        if text.contains("overbilling") || text.contains("overcharged") || text.contains("overcharge") || text.contains("improper fee") { return "Overbilling" }
        if text.contains("wage") || text.contains("hour violation") || text.contains("overtime") || text.contains("unpaid break") { return "Wage and Hour" }
        if text.contains("labor law") || text.contains("employee") || text.contains("employment") || text.contains("worker") { return "Employment" }
        if text.contains("discrimination") || text.contains("discriminat") { return "Discrimination" }
        if text.contains("sexual abuse") || text.contains("sexual assault") { return "Sexual Abuse" }
        if text.contains("child labor") { return "Child Labor" }
        if text.contains("civil rights") { return "Civil Rights" }
        if text.contains("securities") || text.contains("shareholder") || text.contains("investor") || text.contains("stock") { return "Securities" }
        if text.contains("bank") || text.contains("credit union") || text.contains("overdraft") || text.contains("mortgage") || text.contains("loan") || text.contains("credit card") { return "Banking" }
        if text.contains("insurance") || text.contains("insured") || text.contains("total loss") { return "Insurance" }
        if text.contains("real estate") || text.contains("rent") || text.contains("rental") || text.contains("property management") || text.contains("tenant") { return "Real Estate" }
        if text.contains("property right") || text.contains("forfeiture") { return "Property Rights" }
        if text.contains("vehicle") || text.contains(" car ") || text.hasPrefix("car ") || text.contains("truck") || text.contains("automotive") || text.contains("airbag") || text.contains("transmission") { return "Automotive" }
        if text.contains("subscription") || text.contains("renewal") || text.contains("auto-renew") || text.contains("automatic renewal") { return "Subscriptions" }
        if text.contains("wireless") || text.contains("telecom") || text.contains("phone plan") || text.contains("at&t") || text.contains("verizon") || text.contains("t-mobile") || text.contains("comcast") { return "Telecom" }
        if text.contains("health") || text.contains("medical") || text.contains("hospital") || text.contains("patient") || text.contains("pharma") || text.contains("drug") || text.contains("medication") { return "Health" }
        if text.contains("food") || text.contains("beef") || text.contains("pork") || text.contains("chicken") || text.contains("grocery") || text.contains("restaurant") { return "Food" }
        if text.contains("university") || text.contains("college") || text.contains("school") || text.contains("student") || text.contains("education") { return "Education" }
        if text.contains("sports") || text.contains("athlete") || text.contains("ncaa") { return "Sports" }
        if text.contains("gaming") || text.contains("video game") || text.contains("loot box") { return "Gaming Addiction" }
        if text.contains("pet") || text.contains("veterinary") { return "Pets" }
        if text.contains("beauty") || text.contains("cosmetic") || text.contains("skincare") { return "Beauty" }
        if text.contains("ai ") || text.contains("artificial intelligence") || text.contains("generative ai") { return "AI" }
        if text.contains("technology") || text.contains("software") || text.contains("app ") || text.contains("online platform") { return "Technology" }
        if text.contains("spam text") || text.contains("text message") || text.contains("robocall") || text.contains("prerecorded call") { return "Spam Texts" }
        if text.contains("entertainment") || text.contains("streaming") || text.contains("ticket") || text.contains("concert") { return "Entertainment" }
        if text.contains("environment") || text.contains("pollution") || text.contains("contamination") { return "Environmental" }
        if text.contains("consumer protection") { return "Consumer Protection" }
        if text.contains("refrigerator") || text.contains("appliance") || text.contains("wire harness") { return "Defective Product" }
        if text.contains("retail") || text.contains("store") || text.contains("purchase") || text.contains("receipt") || text.contains("merchandise") || text.contains("consumer") { return "Retail" }
        if text.contains("finance") || text.contains("financial") || text.contains("payment") || text.contains("fee") { return "Finance" }
        return "Other"
    }

    private func inferStates(from text: String) -> [String] {
        let lowered = " " + text.lowercased() + " "
        let states = Self.stateNames.filter { state in
            let needle = state.lowercased()
            return lowered.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: needle))\b"#, options: .regularExpression) != nil
        }
        return states
    }

    private func inferNationwide(from text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("united states") ||
            lowered.contains("nationwide") ||
            lowered.contains("u.s. residents") ||
            lowered.contains("us residents") ||
            lowered.contains("all states") {
            return true
        }
        return false
    }

    private func stableSettlementID(title: String, stableKey: String) -> String {
        let slug = title
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = String(slug.prefix(72))
        return "\(prefix)-\(String(format: "%08x", fnv1a32(stableKey)))"
    }

    private func fnv1a32(_ string: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    private func capture(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private func deduplicateAndSort(_ settlements: [Settlement]) -> [Settlement] {
        var byID: [String: Settlement] = [:]
        for settlement in settlements {
            if let existing = byID[settlement.id] {
                if settlement.isFeatured && !existing.isFeatured {
                    byID[settlement.id] = settlement
                } else if settlement.sourceRank < existing.sourceRank {
                    byID[settlement.id] = settlement
                }
            } else {
                byID[settlement.id] = settlement
            }
        }

        return byID.values.sorted {
            if $0.isFeatured != $1.isFeatured { return $0.isFeatured && !$1.isFeatured }
            if $0.sourceRank != $1.sourceRank { return $0.sourceRank < $1.sourceRank }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static let stateNames: [String] = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut",
        "Delaware", "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa",
        "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan",
        "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
        "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma",
        "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas",
        "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming",
        "District of Columbia"
    ]
}

private extension String {
    var trimmedAndCollapsed: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Future foreground refresh hook

final class SettlementRefreshManager {
    static let shared = SettlementRefreshManager()

    private var refreshTask: Task<Void, Never>?

    func refreshIfStale() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            _ = await SettlementScanner.shared.loadAndScan(refreshPolicy: .preferFreshCache)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
