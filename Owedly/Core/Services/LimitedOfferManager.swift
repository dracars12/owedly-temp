import Foundation

final class LimitedOfferManager {
    static let shared = LimitedOfferManager()

    private let defaults: UserDefaults
    private let startedAtKey = "owedly.limitedOffer.startedAt.v1"
    private let expiredKey = "owedly.limitedOffer.expired.v1"
    private let duration: TimeInterval = 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isExpiredForever: Bool { defaults.bool(forKey: expiredKey) }

    var endDate: Date? {
        guard !isExpiredForever else { return nil }
        guard let startedAt = defaults.object(forKey: startedAtKey) as? Date else { return nil }
        return startedAt.addingTimeInterval(duration)
    }

    @discardableResult
    func startIfNeeded(now: Date = Date()) -> Date? {
        guard !PurchaseManager.shared.isPurchased, !isExpiredForever else { return nil }
        if let endDate {
            if endDate <= now {
                expireForever()
                return nil
            }
            return endDate
        }

        defaults.set(now, forKey: startedAtKey)
        return now.addingTimeInterval(duration)
    }

    func remaining(now: Date = Date()) -> TimeInterval {
        guard let endDate else { return 0 }
        let value = endDate.timeIntervalSince(now)
        if value <= 0 {
            expireForever()
            return 0
        }
        return value
    }

    func expireForever() {
        defaults.set(true, forKey: expiredKey)
        defaults.removeObject(forKey: startedAtKey)
    }
}
