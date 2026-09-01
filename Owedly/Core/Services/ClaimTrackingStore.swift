import Foundation

// MARK: - Claim tracking

/// Local-only claim state used by the future My Claims tab.
/// We intentionally store a compact settlement snapshot so a tracked claim can still be
/// displayed if the website catalog changes or the settlement later disappears from cache.
struct TrackedClaim: Codable, Hashable {
    enum State: String, Codable {
        /// The user opened the external filing flow but has not confirmed submitting the form.
        case needsAction
        /// The user confirmed that the external claim form was submitted.
        case filed
    }

    let settlementID: String
    let title: String
    let company: String
    let category: String
    let payoutText: String?
    let deadline: Date?
    let imageURL: URL?
    let officialClaimURL: URL?
    let sourceURL: URL?
    /// Full catalog snapshot for richer My Claims details. Optional keeps v19 records decodable.
    let settlementSnapshot: Settlement?
    var state: State
    let startedAt: Date
    var filedAt: Date?

    init(settlement: Settlement, state: State, date: Date = Date(), existingStartedAt: Date? = nil) {
        settlementID = settlement.id
        title = settlement.title
        company = settlement.company
        category = settlement.category
        payoutText = settlement.payoutText
        deadline = settlement.deadline
        imageURL = settlement.imageURL
        officialClaimURL = settlement.officialClaimURL
        sourceURL = settlement.sourceURL
        settlementSnapshot = settlement
        self.state = state
        startedAt = existingStartedAt ?? date
        filedAt = state == .filed ? date : nil
    }

    func resolvedSettlement(currentCatalog: [Settlement] = SettlementScanner.shared.latestResult?.allSettlements ?? []) -> Settlement {
        if let current = currentCatalog.first(where: { $0.id == settlementID }) {
            return current
        }
        if let settlementSnapshot {
            return settlementSnapshot
        }
        return Settlement(
            id: settlementID,
            title: title,
            company: company,
            shortDescription: "",
            eligibilityDescription: nil,
            category: category,
            payoutText: payoutText,
            deadline: deadline,
            proofRequired: nil,
            eligibleStates: [],
            isNationwide: false,
            classPeriodText: nil,
            officialClaimURL: officialClaimURL,
            sourceURL: sourceURL,
            imageURL: imageURL,
            status: .open,
            createdAt: startedAt,
            updatedAt: filedAt ?? startedAt,
            isFeatured: false,
            sourceRank: Int.max
        )
    }

    /// For the future My Claims UI: an unfiled claim becomes expired after its claim deadline.
    /// A filed claim remains in Tracking because the filing deadline passing does not mean
    /// the administrator has finished reviewing or paying the claim.
    var isExpiredBeforeFiling: Bool {
        guard state == .needsAction, let deadline else { return false }
        return deadline < Date()
    }
}

extension Notification.Name {
    static let owedlyClaimTrackingDidChange = Notification.Name("owedly.claimTrackingDidChange")
    static let owedlyUpcomingWatchDidChange = Notification.Name("owedly.upcomingWatchDidChange")
    static let owedlySettlementScanDidUpdate = Notification.Name("owedly.settlementScanDidUpdate")
}

final class ClaimTrackingStore {
    static let shared = ClaimTrackingStore()

    private let defaults: UserDefaults
    private let storageKey = "owedly.claimTracking.records.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var recordsByID: [String: TrackedClaim]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([String: TrackedClaim].self, from: data) {
            recordsByID = decoded
        } else {
            recordsByID = [:]
        }
    }

    var allRecords: [TrackedClaim] {
        recordsByID.values.sorted { lhs, rhs in
            let lhsDate = lhs.filedAt ?? lhs.startedAt
            let rhsDate = rhs.filedAt ?? rhs.startedAt
            return lhsDate > rhsDate
        }
    }

    var activeRecords: [TrackedClaim] {
        allRecords.filter { !$0.isExpiredBeforeFiling }
    }

    var expiredRecords: [TrackedClaim] {
        allRecords.filter(\.isExpiredBeforeFiling)
    }

    func record(for settlementID: String) -> TrackedClaim? {
        recordsByID[settlementID]
    }

    func markNeedsAction(_ settlement: Settlement, at date: Date = Date()) {
        if var existing = recordsByID[settlement.id] {
            // Never downgrade a confirmed filing merely because the user revisits the website.
            guard existing.state != .filed else { return }
            existing.state = .needsAction
            recordsByID[settlement.id] = existing
        } else {
            recordsByID[settlement.id] = TrackedClaim(settlement: settlement, state: .needsAction, date: date)
        }
        persistAndNotify()
    }

    func markFiled(_ settlement: Settlement, at date: Date = Date()) {
        let startedAt = recordsByID[settlement.id]?.startedAt
        recordsByID[settlement.id] = TrackedClaim(
            settlement: settlement,
            state: .filed,
            date: date,
            existingStartedAt: startedAt
        )
        persistAndNotify()
    }

    func stopTracking(settlementID: String) {
        guard recordsByID.removeValue(forKey: settlementID) != nil else { return }
        persistAndNotify()
    }

    func clearAll() {
        guard !recordsByID.isEmpty else { return }
        recordsByID.removeAll()
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .owedlyClaimTrackingDidChange, object: nil)
    }

    private func persistAndNotify() {
        if let data = try? encoder.encode(recordsByID) {
            defaults.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .owedlyClaimTrackingDidChange, object: nil)
    }
}

// MARK: - Upcoming watch state

/// Keeps the user's explicit "Notify" choices local. Actual server-driven opening alerts can
/// later use these IDs without uploading the user's onboarding/profile data.
final class UpcomingSettlementWatchStore {
    static let shared = UpcomingSettlementWatchStore()

    private let defaults: UserDefaults
    private let storageKey = "owedly.upcomingSettlementWatch.ids.v1"
    private let snapshotsKey = "owedly.upcomingSettlementWatch.snapshots.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var ids: Set<String>
    private var snapshotsByID: [String: Settlement]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = Set(defaults.stringArray(forKey: storageKey) ?? [])
        if let data = defaults.data(forKey: snapshotsKey),
           let decoded = try? decoder.decode([String: Settlement].self, from: data) {
            snapshotsByID = decoded
        } else {
            snapshotsByID = [:]
        }
    }

    var watchedIDs: Set<String> { ids }

    var watchedSettlements: [Settlement] {
        ids.compactMap { snapshotsByID[$0] }
    }

    func isWatching(_ settlementID: String) -> Bool {
        ids.contains(settlementID)
    }

    func watch(_ settlement: Settlement) {
        let previous = snapshotsByID[settlement.id]
        let inserted = ids.insert(settlement.id).inserted
        snapshotsByID[settlement.id] = settlement
        guard inserted || previous != settlement else { return }
        persistAndNotify()
    }

    /// Kept for compatibility with older call sites / saved state. New code should prefer
    /// watch(_ settlement:) so we retain enough data to detect when an upcoming case opens.
    func watch(_ settlementID: String) {
        guard ids.insert(settlementID).inserted else { return }
        persistAndNotify()
    }

    func unwatch(_ settlementID: String) {
        guard ids.remove(settlementID) != nil else { return }
        snapshotsByID.removeValue(forKey: settlementID)
        persistAndNotify()
    }

    func clearAll() {
        guard !ids.isEmpty || !snapshotsByID.isEmpty else { return }
        ids.removeAll()
        snapshotsByID.removeAll()
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: snapshotsKey)
        NotificationCenter.default.post(name: .owedlyUpcomingWatchDidChange, object: nil)
    }

    private func persistAndNotify() {
        defaults.set(Array(ids).sorted(), forKey: storageKey)
        if let data = try? encoder.encode(snapshotsByID) {
            defaults.set(data, forKey: snapshotsKey)
        }
        NotificationCenter.default.post(name: .owedlyUpcomingWatchDidChange, object: nil)
    }
}
