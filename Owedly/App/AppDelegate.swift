import UIKit
import AppTrackingTransparency
import AppsFlyerLib


private enum AppTestingConfiguration {
    // Temporary while the onboarding/intro flow is being iterated. Set to false once the
    // main app should respect the persisted completion flag.
    static let alwaysShowOnboarding = false
    // Main-app foreground scans are enabled. The scanner still respects its local cache TTL,
    // so every foreground performs matching while network refresh only happens when needed.
    static let refreshSettlementsWhenAppBecomesActive = true
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var coordinator: RootCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Keep the launch order aligned with Cleaner: Firebase Core first (Owedly needs RTDB/FCM),
        // then Adapty, AppsFlyer, and finally the ATT-gated analytics/linking coordinator.
        FirebaseBootstrap.configureIfPossible()
        PurchaseManager.shared.configureAtLaunch()
        AppsFlyerBootstrap.shared.configure(launchOptions: launchOptions)
        AnalyticsCoordinator.shared.prepareAtLaunch()
        NotificationManager.shared.configureAtLaunch()

        let window = UIWindow(frame: UIScreen.main.bounds)
        // Owedly is intentionally light-only. Set this before attaching any root controller so
        // status/navigation/tab bar materials never briefly resolve using the system dark style.
        window.overrideUserInterfaceStyle = .light
        window.backgroundColor = DesignSystem.Color.gradientCream
        self.window = window

        let coordinator = RootCoordinator(window: window)
        self.coordinator = coordinator
        coordinator.start()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationManager.shared.handleAPNSToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Notifications] APNs registration failed: \(error)")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // For users who already completed onboarding before this ATT update, request the prompt on
        // the first active foreground. New users still get it at the same onboarding transition as
        // Cleaner (after the first onboarding screen, before moving to screen two).
        AnalyticsCoordinator.shared.handleDidBecomeActive(
            onboardingCompleted: OnboardingStore.shared.draft.onboardingCompleted
        )

        // Subscription state and App Store pricing can both change while Owedly is inactive.
        // Warm the profile + both Adapty placements on every foreground so visible screens never
        // become the first place that has to wait for product metadata.
        Task { await PurchaseManager.shared.refreshForForeground() }

        guard AppTestingConfiguration.refreshSettlementsWhenAppBecomesActive,
              OnboardingStore.shared.draft.onboardingCompleted else { return }
        SettlementRefreshManager.shared.refreshIfStale()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        return true
    }
}


/// Coordinates ATT -> Firebase Analytics -> AppsFlyer start in the same practical order used by
/// Cleaner, adapted for AppsFlyer SDK 7 where `registerSessionReadyListener` replaces the old
/// `waitForATTUserAuthorization` gate.
final class AnalyticsCoordinator {
    static let shared = AnalyticsCoordinator()

    private var sequenceCompletedThisLaunch = false
    private var attRequestInFlight = false
    private var returningUserPromptScheduled = false

    private init() {}

    var needsTrackingAuthorization: Bool {
        if #available(iOS 14.0, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        }
        return false
    }

    func prepareAtLaunch() {
        if #available(iOS 14.0, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            guard status != .notDetermined else {
                // `setAnalyticsCollectionEnabled` is persisted by Firebase across launches.
                // Reassert the gate so upgrades from our earlier analytics-enabled test build do
                // not leak a session before the new ATT prompt has been answered.
                FirebaseBootstrap.pauseAnalyticsUntilTrackingDecision()
                return
            }
            finishTrackingDecision(status: status)
        } else {
            finishTrackingDecision(trackingAuthorized: true)
        }
    }

    func handleDidBecomeActive(onboardingCompleted: Bool) {
        if #available(iOS 14.0, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status != .notDetermined {
                finishTrackingDecision(status: status)
                return
            }

            // Existing users have no onboarding transition left on which to show ATT.
            guard onboardingCompleted,
                  !returningUserPromptScheduled,
                  !attRequestInFlight else { return }
            returningUserPromptScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.requestTrackingAuthorizationIfNeeded(completion: nil)
            }
        } else {
            finishTrackingDecision(trackingAuthorized: true)
        }
    }

    /// Called from the introductory Find My Matches button before entering onboarding.
    /// Completion always returns on the main queue.
    func requestTrackingAuthorizationIfNeeded(completion: (() -> Void)?) {
        guard #available(iOS 14.0, *) else {
            finishTrackingDecision(trackingAuthorized: true)
            DispatchQueue.main.async { completion?() }
            return
        }

        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        guard currentStatus == .notDetermined else {
            finishTrackingDecision(status: currentStatus)
            DispatchQueue.main.async { completion?() }
            return
        }

        guard !attRequestInFlight else { return }
        attRequestInFlight = true

        // Apple requires the app to be active when presenting ATT. The onboarding call already is,
        // but this guard also makes the returning-user fallback resilient to lifecycle timing.
        guard UIApplication.shared.applicationState == .active else {
            attRequestInFlight = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.requestTrackingAuthorizationIfNeeded(completion: completion)
            }
            return
        }

        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }
                self.attRequestInFlight = false
                self.finishTrackingDecision(status: status)
                completion?()
            }
        }
    }

    @available(iOS 14.0, *)
    private func finishTrackingDecision(status: ATTrackingManager.AuthorizationStatus) {
        finishTrackingDecision(trackingAuthorized: status == .authorized)
    }

    private func finishTrackingDecision(trackingAuthorized: Bool) {
        // Re-apply consent on every foreground in case the user changed ATT in Settings while the
        // process stayed alive. Only the AppsFlyer first-session release is one-shot per launch.
        let immediateID: String?
        if FirebaseBootstrap.isConfigured {
            immediateID = FirebaseBootstrap.enableAnalyticsAfterTrackingDecision(
                trackingAuthorized: trackingAuthorized
            )
        } else {
            immediateID = nil
        }

        guard !sequenceCompletedThisLaunch else { return }
        sequenceCompletedThisLaunch = true

        guard FirebaseBootstrap.isConfigured else {
            AppsFlyerBootstrap.shared.trackingDecisionDidComplete(customerUserID: nil)
            return
        }

        resolveFirebaseIdentityAndReleaseAppsFlyer(immediateID: immediateID, attempt: 0)
    }

    private func resolveFirebaseIdentityAndReleaseAppsFlyer(
        immediateID: String?,
        attempt: Int
    ) {
        if let appInstanceID = immediateID ?? FirebaseBootstrap.currentAnalyticsAppInstanceID,
           !appInstanceID.isEmpty {
            // Cleaner uses Firebase's App Instance ID as the AppsFlyer CUID. Set it before the
            // first AppsFlyer `start`, and also attach the same installation to Adapty.
            AppsFlyerBootstrap.shared.trackingDecisionDidComplete(customerUserID: appInstanceID)
            Task {
                await PurchaseManager.shared.linkFirebaseAppInstanceID(appInstanceID)
            }
            return
        }

        // Firebase can create the installation ID asynchronously. Give it a short bounded window
        // so AppsFlyer's install event gets the same CUID whenever possible, but never block launch.
        guard attempt < 4 else {
            AppsFlyerBootstrap.shared.trackingDecisionDidComplete(customerUserID: nil)
            return
        }

        let delays: [TimeInterval] = [0.35, 0.65, 1.0, 1.5]
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            self?.resolveFirebaseIdentityAndReleaseAppsFlyer(immediateID: nil, attempt: attempt + 1)
        }
    }
}


private final class AppsFlyerBootstrap: NSObject, AppsFlyerLibDelegate, AppsFlyerDeepLinkDelegate {
    static let shared = AppsFlyerBootstrap()

    private let devKey = "Bkn5HUTb5yuzaK9BnGvRSM"
    private let appleAppID = "6802624438"
    private let lock = NSLock()

    private var configured = false
    private var sdkReadyForCurrentForeground = false
    private var trackingDecisionReady = false
    private var customerUserID: String?

    private override init() {
        super.init()
    }

    func configure(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard !configured else { return }
        configured = true

        let sdk = AppsFlyerLib.shared()
        // AppsFlyer 7 credentials must be initialized before every other SDK call.
        sdk.initialize(devKey: devKey, appId: appleAppID)
        sdk.delegate = self
        sdk.deepLinkDelegate = self

        // Universal-link cold-launch context must be supplied before the readiness listener.
        sdk.handleLaunchOptions(launchOptions)

        // SDK 7 fires this once per foreground cycle. We deliberately do not call `start` until
        // ATT has been answered (or was already determined), reproducing Cleaner's ATT gate with
        // the current AppsFlyer session model.
        sdk.registerSessionReadyListener { [weak self] in
            self?.sessionDidBecomeReady()
        }
    }

    func trackingDecisionDidComplete(customerUserID: String?) {
        lock.lock()
        trackingDecisionReady = true
        if let customerUserID, !customerUserID.isEmpty {
            self.customerUserID = customerUserID
        }
        lock.unlock()
        startIfReady()
    }

    private func sessionDidBecomeReady() {
        lock.lock()
        sdkReadyForCurrentForeground = true
        lock.unlock()
        startIfReady()
    }

    private func startIfReady() {
        lock.lock()
        guard trackingDecisionReady, sdkReadyForCurrentForeground else {
            lock.unlock()
            return
        }
        sdkReadyForCurrentForeground = false
        let currentCustomerUserID = customerUserID
        lock.unlock()

        let sdk = AppsFlyerLib.shared()
        if let currentCustomerUserID, !currentCustomerUserID.isEmpty {
            // AppsFlyer requires CUID to be set on every launch and before `start` if it should be
            // associated with the install/session event.
            sdk.customerUserID = currentCustomerUserID
        }
        sdk.start()
    }

    func onConversionDataSuccess(_ installData: [AnyHashable: Any]) {
        #if DEBUG
        let status = installData["af_status"] ?? "unknown"
        let source = installData["media_source"] ?? "unknown"
        let campaign = installData["campaign"] ?? "unknown"
        print("[AppsFlyer] Conversion: status=\(status), source=\(source), campaign=\(campaign)")
        #endif

        // Same bridge as Cleaner, updated for Adapty 4.1 naming: first set AppsFlyer UID on the
        // Adapty profile, then forward AppsFlyer install attribution to Adapty.
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        Task {
            await PurchaseManager.shared.linkAppsFlyer(uid: uid, conversionData: installData)
        }
    }

    func onConversionDataFail(_ error: Error!) {
        print("[AppsFlyer] Conversion data failed: \(error?.localizedDescription ?? "Unknown error")")
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        switch result.status {
        case .found:
            #if DEBUG
            print("[AppsFlyer] Deep link resolved: \(result.deepLink?.deeplinkValue ?? "<no deep_link_value>")")
            #endif
            // Routing can be attached here once product deep-link destinations are defined.
        case .failure:
            print("[AppsFlyer] Deep link resolution failed: \(result.error?.localizedDescription ?? "Unknown error")")
        case .notFound:
            break
        @unknown default:
            break
        }
    }
}


final class RootCoordinator {
    private let window: UIWindow
    private weak var introStageNavigationController: UINavigationController?

    init(window: UIWindow) {
        self.window = window
    }

    func start() {
        if AppTestingConfiguration.alwaysShowOnboarding {
            OnboardingStore.shared.update { $0.onboardingCompleted = false }
        }

        let splash = SplashViewController()
        splash.onFinished = { [weak self] in
            guard let self else { return }
            if OnboardingStore.shared.draft.onboardingCompleted {
                self.showMainApp(animated: true)
            } else {
                self.showIntro(animated: true)
            }
        }
        setRoot(splash, animated: false)
        window.makeKeyAndVisible()
    }

    private func showIntro(animated: Bool) {
        let intro = IntroViewController()
        intro.onFindMatches = { [weak self] in self?.showOnboarding() }
        setRoot(intro, animated: animated)
    }

    private func showOnboarding() {
        let onboarding = OnboardingViewController()
        let navigation = UINavigationController(rootViewController: onboarding)
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.view.backgroundColor = DesignSystem.Color.gradientCream
        introStageNavigationController = navigation

        onboarding.onBackToIntro = { [weak self] in self?.showIntro(animated: true) }
        onboarding.onFinished = { [weak self, weak navigation] in
            guard let self, let navigation else { return }
            self.pushPreparingMatches(on: navigation)
        }

        // The pseudo-screen onboarding chrome still appears fully static; the navigation
        // controller is hidden and exists only so the next product section can use true pushes.
        setRoot(navigation, animated: false)
    }

    private func pushPreparingMatches(on navigation: UINavigationController) {
        let controller = PreparingMatchesViewController()
        controller.onFinished = { [weak self, weak navigation] result in
            guard let self, let navigation else { return }
            self.pushPayoutInsight(result: result, on: navigation)
        }
        navigation.pushViewController(controller, animated: true)
    }

    private func pushPayoutInsight(result: SettlementScanResult, on navigation: UINavigationController) {
        let controller = PayoutInsightViewController()
        controller.onContinue = { [weak self, weak controller, weak navigation] in
            guard let self, let controller, let navigation else { return }
            self.presentPaywall(from: controller, result: result, navigation: navigation)
        }
        navigation.pushViewController(controller, animated: true)
    }

    private func presentPaywall(
        from presenter: UIViewController,
        result: SettlementScanResult,
        navigation: UINavigationController
    ) {
        let paywall = PaywallViewController(scanResult: result)

        paywall.onClose = { [weak self, weak paywall, weak navigation] in
            guard let self, let paywall, let navigation else { return }
            paywall.dismiss(animated: true) {
                self.pushNotifications(on: navigation)
            }
        }

        let entitlementSuccess: () -> Void = { [weak self, weak paywall, weak presenter, weak navigation] in
            guard let self, let paywall, let presenter, let navigation else { return }
            paywall.dismiss(animated: true) {
                let success = PaymentSuccessViewController()
                success.modalPresentationStyle = .fullScreen
                success.onViewMatches = { [weak self, weak success, weak navigation] in
                    guard let self, let success, let navigation else { return }
                    success.dismiss(animated: true) {
                        self.pushNotifications(on: navigation)
                    }
                }
                presenter.present(success, animated: true)
            }
        }
        paywall.onPurchaseSuccess = entitlementSuccess
        paywall.onRestoreSuccess = entitlementSuccess

        presenter.present(paywall, animated: true)
    }

    private func pushNotifications(on navigation: UINavigationController) {
        if navigation.topViewController is NotificationsViewController { return }
        let controller = NotificationsViewController()
        controller.onFinished = { [weak self] in
            OnboardingStore.shared.markCompleted()
            self?.showMainApp(animated: true)
        }
        navigation.pushViewController(controller, animated: true)
    }

    private func showMainApp(animated: Bool) {
        introStageNavigationController = nil
        setRoot(MainTabBarController(), animated: animated)
    }

    private func setRoot(_ viewController: UIViewController, animated: Bool) {
        guard animated, window.rootViewController != nil else {
            UIView.performWithoutAnimation {
                window.rootViewController = viewController
                window.layoutIfNeeded()
            }
            return
        }

        let snapshot = window.snapshotView(afterScreenUpdates: false)
        snapshot?.frame = window.bounds
        snapshot?.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        UIView.performWithoutAnimation {
            window.rootViewController = viewController
            viewController.view.frame = window.bounds
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
            window.layoutIfNeeded()
        }

        guard let snapshot else { return }
        window.addSubview(snapshot)
        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }
}
