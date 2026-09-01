import UIKit
import SnapKit

final class MainTabBarController: UITabBarController {
    private var blurredTabBarAppearance: UITabBarAppearance!
    private var transparentTabBarAppearance: UITabBarAppearance!

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.overrideUserInterfaceStyle = .light
        tabBar.overrideUserInterfaceStyle = .light
        configureTabBar()

        let discover = UINavigationController(rootViewController: DiscoverViewController())
        discover.overrideUserInterfaceStyle = .light
        discover.view.overrideUserInterfaceStyle = .light
        discover.navigationBar.overrideUserInterfaceStyle = .light
        discover.setNavigationBarHidden(false, animated: false)
        discover.navigationBar.prefersLargeTitles = false
        if #unavailable(iOS 26.0) { discover.navigationBar.tintColor = .black }
        discover.tabBarItem = UITabBarItem(title: "Discover", image: UIImage(systemName: "globe"), selectedImage: UIImage(systemName: "globe"))

        let claims = UINavigationController(rootViewController: MyClaimsViewController())
        claims.overrideUserInterfaceStyle = .light
        claims.view.overrideUserInterfaceStyle = .light
        claims.navigationBar.overrideUserInterfaceStyle = .light
        claims.setNavigationBarHidden(false, animated: false)
        claims.navigationBar.prefersLargeTitles = false
        if #unavailable(iOS 26.0) { claims.navigationBar.tintColor = .black }
        claims.tabBarItem = UITabBarItem(title: "My Claims", image: UIImage(systemName: "dollarsign.circle"), selectedImage: UIImage(systemName: "dollarsign.circle"))

        viewControllers = [discover, claims]
        selectedIndex = 0
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tabBar.layer.cornerRadius = 16
        tabBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        if #available(iOS 26.0, *) {
            tabBar.layer.borderWidth = 0
            tabBar.layer.borderColor = UIColor.clear.cgColor
        } else {
            tabBar.layer.borderWidth = 0.5
            tabBar.layer.borderColor = UIColor.black.withAlphaComponent(0.14).cgColor
        }
        tabBar.clipsToBounds = true
    }

    private func configureTabBar() {
        tabBar.tintColor = DesignSystem.Color.brandGreen
        tabBar.unselectedItemTintColor = UIColor(hex: 0x999999)
        tabBar.itemPositioning = .fill

        let blurred = UITabBarAppearance()
        blurred.configureWithDefaultBackground()
        blurred.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        blurred.backgroundColor = UIColor.white.withAlphaComponent(0.74)
        blurred.shadowColor = UIColor.black.withAlphaComponent(0.20)
        blurred.stackedLayoutAppearance.selected.iconColor = DesignSystem.Color.brandGreen
        blurred.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: DesignSystem.Color.brandGreen]
        blurred.stackedLayoutAppearance.normal.iconColor = UIColor(hex: 0x999999)
        blurred.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: 0x999999)]
        blurredTabBarAppearance = blurred

        let transparent = UITabBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.backgroundColor = .clear
        transparent.shadowColor = .clear
        transparent.stackedLayoutAppearance.selected.iconColor = DesignSystem.Color.brandGreen
        transparent.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: DesignSystem.Color.brandGreen]
        transparent.stackedLayoutAppearance.normal.iconColor = UIColor(hex: 0x999999)
        transparent.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: 0x999999)]
        transparentTabBarAppearance = transparent

        tabBar.standardAppearance = blurred
        tabBar.scrollEdgeAppearance = transparent
    }

    /// On iOS 26 UIKit can observe the exact content scroll view through
    /// `setContentScrollView(_:for:)`. Older systems infer the scroll view from the view
    /// hierarchy, which is unreliable for Discover because it also contains a horizontal
    /// collection view. This fallback mirrors scroll-edge behavior explicitly: blur while
    /// there is content continuing underneath the tab bar, transparent when the content edge
    /// has reached it (or there is no list content at all).
    func updateBottomBarAppearance(for scrollView: UIScrollView?) {
        guard #unavailable(iOS 26.0) else { return }

        guard let scrollView, !scrollView.isHidden, scrollView.bounds.height > 0 else {
            applyLegacyTabBarAppearance(blurred: false)
            return
        }

        let contentBottom = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
        let hasContentUnderTabBar = contentBottom > visibleBottom + 1
        applyLegacyTabBarAppearance(blurred: hasContentUnderTabBar)
    }

    private func applyLegacyTabBarAppearance(blurred: Bool) {
        let appearance = blurred ? blurredTabBarAppearance : transparentTabBarAppearance
        guard let appearance else { return }

        // Assign both appearances on iOS 15–18. If UIKit happens to infer the wrong nested
        // scroll view it can otherwise keep selecting scrollEdgeAppearance forever.
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}
