import Foundation
import UIKit
import FirebaseCore
import FirebaseAnalytics

enum FirebaseBootstrap {
    @discardableResult
    static func configureIfPossible() -> Bool {
        if FirebaseApp.app() != nil { return true }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Firebase] GoogleService-Info.plist not found. Running without Firebase services.")
            return false
        }

        FirebaseApp.configure()
        return FirebaseApp.app() != nil
    }

    /// Explicitly pauses Analytics while ATT is still undecided. This matters not only for fresh
    /// installs: Firebase persists a programmatic collection setting across launches, so a tester
    /// upgrading from an earlier build that enabled Analytics must be put back behind the ATT gate.
    static func pauseAnalyticsUntilTrackingDecision() {
        guard isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(false)
    }

    /// Mirrors the analytics bootstrap used in Cleaner while respecting the user's ATT choice.
    /// Firebase Core is configured at launch because Owedly also needs Messaging / Realtime DB,
    /// but Analytics collection itself stays disabled by Info.plist until this method is called.
    @discardableResult
    static func enableAnalyticsAfterTrackingDecision(trackingAuthorized: Bool) -> String? {
        guard isConfigured else { return nil }

        let userID = UIDevice.current.identifierForVendor?.uuidString
        if let userID {
            Analytics.setUserID(userID)
            Analytics.setDefaultEventParameters(["user_id": userID])
        }

        Analytics.setConsent([
            .analyticsStorage: .granted,
            .adStorage: trackingAuthorized ? .granted : .denied,
            .adUserData: trackingAuthorized ? .granted : .denied,
            .adPersonalization: trackingAuthorized ? .granted : .denied
        ])
        Analytics.setUserProperty(
            trackingAuthorized ? "true" : "false",
            forName: AnalyticsUserPropertyAllowAdPersonalizationSignals
        )
        Analytics.setAnalyticsCollectionEnabled(true)

        return Analytics.appInstanceID()
    }

    static var currentAnalyticsAppInstanceID: String? {
        guard isConfigured else { return nil }
        return Analytics.appInstanceID()
    }

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }
}
