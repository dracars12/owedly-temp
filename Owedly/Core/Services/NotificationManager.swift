import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var isMonitoringNewSettlements = false
    private var didConfigureObservers = false

    private let seenMatchesKey = "owedly.notifications.seenPotentialMatches.v1"
    private let openedWatchAlertsKey = "owedly.notifications.openedWatchAlerts.v1"
    private let settlementAlertsEnabledKey = "owedly.notifications.settlementAlertsEnabled.v1"
    private let deadlineRemindersEnabledKey = "owedly.notifications.deadlineRemindersEnabled.v1"

    var settlementAlertsEnabled: Bool {
        get { defaults.object(forKey: settlementAlertsEnabledKey) == nil ? true : defaults.bool(forKey: settlementAlertsEnabledKey) }
        set { defaults.set(newValue, forKey: settlementAlertsEnabledKey) }
    }

    var deadlineRemindersEnabled: Bool {
        get { defaults.object(forKey: deadlineRemindersEnabledKey) == nil ? true : defaults.bool(forKey: deadlineRemindersEnabledKey) }
        set { defaults.set(newValue, forKey: deadlineRemindersEnabledKey) }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    func clearPersonalInformation() {
        defaults.removeObject(forKey: seenMatchesKey)
        defaults.removeObject(forKey: openedWatchAlertsKey)
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func configureAtLaunch() {
        center.delegate = self
        if FirebaseBootstrap.isConfigured {
            Messaging.messaging().delegate = self
        }

        guard !didConfigureObservers else { return }
        didConfigureObservers = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(claimTrackingDidChange),
            name: .owedlyClaimTrackingDidChange,
            object: nil
        )
    }

    func refreshIfAlreadyAuthorized(scanResult: SettlementScanResult) async {
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await activateRemoteNotificationsIfAvailable()
        if deadlineRemindersEnabled {
            await scheduleDeadlineReminders(for: scanResult)
            await scheduleClaimTrackingReminders()
        } else {
            await removePending(withPrefixes: ["owedly.deadline.", "owedly.claim.action.", "owedly.claim.tracking."])
        }

        if settlementAlertsEnabled {
            await notifyAboutNewMatchesIfNeeded(scanResult)
            await notifyIfWatchedUpcomingOpened(scanResult)
            startNewSettlementMonitoring()
        } else {
            stopNewSettlementMonitoring()
        }
    }

    @discardableResult
    func setSettlementAlertsEnabled(_ enabled: Bool) async -> Bool {
        settlementAlertsEnabled = enabled
        guard enabled else {
            stopNewSettlementMonitoring()
            await removePending(withPrefixes: ["owedly.new.", "owedly.upcoming.opened."])
            return false
        }

        let settings = await notificationSettings()
        let authorized: Bool
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            authorized = true
        } else {
            authorized = await requestAuthorizationAndActivate()
        }

        if !authorized { settlementAlertsEnabled = false }
        if authorized, let result = SettlementScanner.shared.latestResult {
            await seedSeenMatchesIfNeeded(result)
            await notifyIfWatchedUpcomingOpened(result)
            startNewSettlementMonitoring()
        }
        return authorized
    }

    @discardableResult
    func setDeadlineRemindersEnabled(_ enabled: Bool) async -> Bool {
        deadlineRemindersEnabled = enabled
        guard enabled else {
            await removePending(withPrefixes: ["owedly.deadline.", "owedly.claim.action.", "owedly.claim.tracking."])
            return false
        }

        let settings = await notificationSettings()
        let authorized: Bool
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            authorized = true
        } else {
            authorized = await requestAuthorizationAndActivate()
        }

        if !authorized { deadlineRemindersEnabled = false }
        if authorized {
            if let result = SettlementScanner.shared.latestResult {
                await scheduleDeadlineReminders(for: result)
            }
            await scheduleClaimTrackingReminders()
        }
        return authorized
    }

    func requestAuthorizationAndActivate() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return false }

            await activateRemoteNotificationsIfAvailable()

            if let result = SettlementScanner.shared.latestResult {
                // The first authorized scan seeds the seen-match set instead of spamming the
                // user with every existing match. Future scans can then alert only on new ones.
                if deadlineRemindersEnabled {
                    await scheduleDeadlineReminders(for: result)
                    await scheduleClaimTrackingReminders()
                }
                if settlementAlertsEnabled {
                    await seedSeenMatchesIfNeeded(result)
                    await notifyIfWatchedUpcomingOpened(result)
                }
            } else if deadlineRemindersEnabled {
                await scheduleClaimTrackingReminders()
            }
            if settlementAlertsEnabled { startNewSettlementMonitoring() }
            return true
        } catch {
            print("[Notifications] authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Offer deadline reminders

    /// Schedules the two most useful reminders for the nearest untracked matches: three days
    /// before and one day before the claim deadline. Keeping the set intentionally small avoids
    /// iOS's pending-local-notification limit while still covering the most urgent cases.
    func scheduleDeadlineReminders(for scanResult: SettlementScanResult) async {
        guard deadlineRemindersEnabled else {
            await removePending(withPrefixes: ["owedly.deadline."])
            return
        }
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await removePending(withPrefixes: ["owedly.deadline."])

        let trackedIDs = Set(ClaimTrackingStore.shared.allRecords.map(\.settlementID))
        let now = Date()

        let matchedSettlements: [Settlement] = scanResult.potentialMatches.map { match in
            match.settlement
        }
        let openUntrackedSettlements: [Settlement] = matchedSettlements.filter { settlement in
            settlement.status == .open && !trackedIDs.contains(settlement.id)
        }
        let futureSettlements: [Settlement] = openUntrackedSettlements.filter { settlement in
            guard let deadline = settlement.deadline else { return false }
            return deadline > now
        }
        let sortedSettlements: [Settlement] = futureSettlements.sorted { lhs, rhs in
            let lhsDeadline = lhs.deadline ?? .distantFuture
            let rhsDeadline = rhs.deadline ?? .distantFuture
            return lhsDeadline < rhsDeadline
        }
        let candidates = Array(sortedSettlements.prefix(10))

        for settlement in candidates {
            guard let deadline = settlement.deadline else { continue }
            await scheduleDeadlineNotification(
                settlement: settlement,
                deadline: deadline,
                daysBefore: 3,
                identifierSuffix: "3d",
                title: "Claim deadline in 3 days",
                body: "\(settlement.title) closes in 3 days. Review eligibility and file before \(Self.dateFormatter.string(from: deadline))."
            )
            await scheduleDeadlineNotification(
                settlement: settlement,
                deadline: deadline,
                daysBefore: 1,
                identifierSuffix: "1d",
                title: "Claim deadline tomorrow",
                body: "\(settlement.title) has a filing deadline tomorrow. Open Owedly to review the claim."
            )
        }
    }

    // MARK: - My Claims reminders

    private func scheduleClaimTrackingReminders() async {
        guard deadlineRemindersEnabled else {
            await removePending(withPrefixes: ["owedly.claim.action.", "owedly.claim.tracking."])
            return
        }
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await removePending(withPrefixes: ["owedly.claim.action.", "owedly.claim.tracking."])

        let needsAction = ClaimTrackingStore.shared.activeRecords
            .filter { $0.state == .needsAction }
            .filter { ($0.deadline ?? .distantPast) > Date() }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .prefix(8)

        for claim in needsAction {
            guard let deadline = claim.deadline else { continue }
            await scheduleClaimActionNotification(claim, deadline: deadline, daysBefore: 3, suffix: "3d")
            await scheduleClaimActionNotification(claim, deadline: deadline, daysBefore: 1, suffix: "1d")
            await scheduleClaimActionNotification(claim, deadline: deadline, daysBefore: 0, suffix: "today")
        }

        // We do not pretend to know the administrator's live review status yet. Instead, one
        // honest check-in reminds the user to review the official website after filing.
        let filed = ClaimTrackingStore.shared.activeRecords
            .filter { $0.state == .filed }
            .prefix(8)

        for claim in filed {
            let filedDate = claim.filedAt ?? claim.startedAt
            guard let checkInDate = Calendar.current.date(byAdding: .day, value: 14, to: filedDate),
                  checkInDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Claim tracking check-in"
            content.body = "You filed \(claim.title). Check the official settlement website for any administrator updates."
            content.sound = .default
            content.userInfo = ["settlementID": claim.settlementID, "kind": "tracking_checkin"]

            var components = Calendar.current.dateComponents([.year, .month, .day], from: checkInDate)
            components.hour = 10
            components.minute = 0
            let request = UNNotificationRequest(
                identifier: "owedly.claim.tracking.\(claim.settlementID).14d",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            await add(request)
        }
    }

    private func scheduleClaimActionNotification(
        _ claim: TrackedClaim,
        deadline: Date,
        daysBefore: Int,
        suffix: String
    ) async {
        guard let reminderDay = Calendar.current.date(byAdding: .day, value: -daysBefore, to: deadline) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = daysBefore == 0 ? 9 : 10
        components.minute = 0
        guard let fireDate = Calendar.current.date(from: components), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        if daysBefore == 0 {
            content.title = "Finish your claim today"
            content.body = "You started \(claim.title), but haven’t marked it filed. Its claim deadline is today."
        } else if daysBefore == 1 {
            content.title = "Finish your claim tomorrow"
            content.body = "You started \(claim.title), but haven’t marked it filed. The deadline is tomorrow."
        } else {
            content.title = "Finish your claim in \(daysBefore) days"
            content.body = "You started \(claim.title), but haven’t marked it filed. The deadline is \(Self.dateFormatter.string(from: deadline))."
        }
        content.sound = .default
        content.userInfo = ["settlementID": claim.settlementID, "kind": "claim_action"]

        let request = UNNotificationRequest(
            identifier: "owedly.claim.action.\(claim.settlementID).\(suffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        await add(request)
    }

    private func scheduleDeadlineNotification(
        settlement: Settlement,
        deadline: Date,
        daysBefore: Int,
        identifierSuffix: String,
        title: String,
        body: String
    ) async {
        guard let reminderDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: deadline),
              reminderDate > Date() else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = 10
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["settlementID": settlement.id, "kind": "deadline"]

        let request = UNNotificationRequest(
            identifier: "owedly.deadline.match.\(settlement.id).\(identifierSuffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        await add(request)
    }

    // MARK: - New matches and watched Upcoming settlements

    private func seedSeenMatchesIfNeeded(_ scanResult: SettlementScanResult) async {
        guard defaults.array(forKey: seenMatchesKey) == nil else { return }
        let trackedIDs = Set(ClaimTrackingStore.shared.allRecords.map(\.settlementID))
        let ids = scanResult.potentialMatches.map(\.settlement).filter { !trackedIDs.contains($0.id) }.map(\.id)
        defaults.set(Array(Set(ids)).sorted(), forKey: seenMatchesKey)
    }

    private func notifyAboutNewMatchesIfNeeded(_ scanResult: SettlementScanResult) async {
        guard settlementAlertsEnabled else { return }
        let trackedIDs = Set(ClaimTrackingStore.shared.allRecords.map(\.settlementID))
        let currentMatches = scanResult.potentialMatches
            .map(\.settlement)
            .filter { !trackedIDs.contains($0.id) }

        guard let stored = defaults.stringArray(forKey: seenMatchesKey) else {
            defaults.set(Array(Set(currentMatches.map(\.id))).sorted(), forKey: seenMatchesKey)
            return
        }

        var seen = Set(stored)
        let newMatches = currentMatches.filter { !seen.contains($0.id) }.prefix(3)
        for settlement in newMatches {
            await postImmediateNewSettlementAlert(settlement)
        }
        seen.formUnion(currentMatches.map(\.id))
        defaults.set(Array(seen).sorted(), forKey: seenMatchesKey)
    }

    private func notifyIfWatchedUpcomingOpened(_ scanResult: SettlementScanResult) async {
        guard settlementAlertsEnabled else { return }
        let watchedStore = UpcomingSettlementWatchStore.shared
        guard !watchedStore.watchedIDs.isEmpty else { return }

        let openSettlements = scanResult.allSettlements.filter { $0.status == .open }
        var alertedIDs = Set(defaults.stringArray(forKey: openedWatchAlertsKey) ?? [])

        for watchedID in watchedStore.watchedIDs {
            let snapshot = watchedStore.watchedSettlements.first(where: { $0.id == watchedID })
            let opened = openSettlements.first(where: { $0.id == watchedID })
                ?? snapshot.flatMap { watched in
                    openSettlements.first(where: { Self.likelySameSettlement(watched, $0) })
                }

            guard let opened, !alertedIDs.contains(watchedID) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Claims are now open"
            content.body = "\(opened.title) now appears in the open settlement catalog. Review eligibility and file if you qualify."
            content.sound = .default
            content.userInfo = ["settlementID": opened.id, "kind": "upcoming_opened"]
            let request = UNNotificationRequest(
                identifier: "owedly.upcoming.opened.\(watchedID)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            await add(request)
            alertedIDs.insert(watchedID)
            watchedStore.unwatch(watchedID)
        }

        defaults.set(Array(alertedIDs).sorted(), forKey: openedWatchAlertsKey)
    }

    private static func likelySameSettlement(_ lhs: Settlement, _ rhs: Settlement) -> Bool {
        let lhsCompany = normalized(lhs.company)
        let rhsCompany = normalized(rhs.company)
        let companyCompatible = !lhsCompany.isEmpty && !rhsCompany.isEmpty &&
            (lhsCompany == rhsCompany || lhsCompany.contains(rhsCompany) || rhsCompany.contains(lhsCompany))
        guard companyCompatible else { return false }

        let ignored: Set<String> = ["class", "action", "settlement", "settlements", "lawsuit", "case", "the", "and", "for", "of", "a", "an"]
        let lhsWords = Set(normalized(lhs.title).split(separator: " ").map(String.init)).subtracting(ignored)
        let rhsWords = Set(normalized(rhs.title).split(separator: " ").map(String.init)).subtracting(ignored)
        guard !lhsWords.isEmpty, !rhsWords.isEmpty else { return true }
        let common = lhsWords.intersection(rhsWords).count
        return common >= 2 || Double(common) / Double(min(lhsWords.count, rhsWords.count)) >= 0.45
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    // MARK: - Remote notification plumbing

    func startNewSettlementMonitoring() {
        // True background/terminated-app delivery still needs a trusted backend/Cloud Function.
        // The current MVP performs local alerts after the iPhone's foreground/catalog scan and
        // keeps FCM/APNs registration ready for the later server-driven layer.
        isMonitoringNewSettlements = true
    }

    func stopNewSettlementMonitoring() {
        isMonitoringNewSettlements = false
    }

    func handleAPNSToken(_ token: Data) {
        guard FirebaseBootstrap.isConfigured else { return }
        Messaging.messaging().apnsToken = token
    }

    private func activateRemoteNotificationsIfAvailable() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if FirebaseBootstrap.isConfigured {
            Messaging.messaging().delegate = self
            Messaging.messaging().isAutoInitEnabled = true
        }
    }

    private func postImmediateNewSettlementAlert(_ settlement: Settlement) async {
        let content = UNMutableNotificationContent()
        content.title = "New Settlement Match"
        content.body = "A new \(settlement.category.lowercased()) settlement may match your profile: \(settlement.title)."
        content.sound = .default
        content.userInfo = ["settlementID": settlement.id, "kind": "new_settlement"]
        let request = UNNotificationRequest(
            identifier: "owedly.new.\(settlement.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        await add(request)
    }

    @objc private func claimTrackingDidChange() {
        Task { [weak self] in
            guard let self, self.deadlineRemindersEnabled else { return }
            await self.scheduleClaimTrackingReminders()
            if let result = SettlementScanner.shared.latestResult {
                await self.scheduleDeadlineReminders(for: result)
            }
        }
    }

    // MARK: - UNUserNotificationCenter async helpers

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func removePending(withPrefixes prefixes: [String]) async {
        let pending = await pendingRequests()
        let ids = pending.map(\.identifier).filter { id in
            prefixes.contains { id.hasPrefix($0) }
        }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error { print("[Notifications] scheduling error: \(error)") }
                continuation.resume()
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

extension NotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        print("[FirebaseMessaging] FCM token: \(fcmToken)")
        // No user/profile data is uploaded in MVP. A future trusted backend can associate
        // this token with a server-side subscription when that architecture is introduced.
    }
}
