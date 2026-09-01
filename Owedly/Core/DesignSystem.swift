import UIKit

// MARK: - App design system
// Shared tokens are taken from the 393pt Figma onboarding/welcome frames.
// Screen-specific values only remain where the Figma composition is genuinely unique.
enum DesignSystem {
    enum Color {
        static let gradientCream = UIColor(hex: 0xFFF5EB)
        static let gradientMint = UIColor(hex: 0xEFFBF7)
        static let gradientBlue = UIColor(hex: 0xEEF2FC)

        static let textPrimary = UIColor.black
        static let textSecondary = UIColor.black.withAlphaComponent(0.50)
        static let textTertiary = UIColor.black.withAlphaComponent(0.18)

        static let brandGreen = UIColor(hex: 0x05945E)
        static let brandGreenDark = UIColor(hex: 0x047C50)
        static let cardFill = UIColor.white.withAlphaComponent(0.50)
        static let selectedCardFill = UIColor(
            red: 210.0 / 255.0,
            green: 236.0 / 255.0,
            blue: 226.0 / 255.0,
            alpha: 0.55
        )
        static let cardBorder = UIColor.black.withAlphaComponent(0.10)
        static let progressTrack = UIColor.black.withAlphaComponent(0.06)
        static let searchFill = UIColor.white
        static let iconBlue = UIColor(hex: 0x008DFF)
    }

    // Reusable spacing scale. Prefer these instead of one-off numbers in views.
    enum Spacing {
        static let x2: CGFloat = 2
        static let x6: CGFloat = 6
        static let x8: CGFloat = 8
        static let x10: CGFloat = 10
        static let x12: CGFloat = 12
        static let x13: CGFloat = 13
        static let x16: CGFloat = 16
        static let x17: CGFloat = 17
        static let x18: CGFloat = 18
        static let x24: CGFloat = 24
        static let x31: CGFloat = 31
        static let x32: CGFloat = 32
        static let x43: CGFloat = 43
        static let x47: CGFloat = 47
        static let x48: CGFloat = 48
        static let x55: CGFloat = 55
        static let x82: CGFloat = 82
    }

    enum Size {
        static let progressHeight: CGFloat = 6
        static let navigationRowHeight: CGFloat = 36
        static let selectionIcon: CGFloat = 24
        static let helperIcon: CGFloat = 20
        static let searchIcon: CGFloat = 19
        static let searchHeight: CGFloat = 43
        static let rowHeight: CGFloat = 56
        static let primaryButtonHeight: CGFloat = 56
        static let companyIcon: CGFloat = 48
        static let companyCardHeight: CGFloat = 109
        static let companyGridWidth: CGFloat = 360
        static let logo = CGSize(width: 197, height: 67)
        static let introMatchCardHeight: CGFloat = 101
        static let introGoogleBadge: CGFloat = 44
        static let introGoogleMark: CGFloat = 34
        static let introSearchIcon: CGFloat = 39
        static let statusDot: CGFloat = 8
        static let introTitleWidth: CGFloat = 258
    }

    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 12
        static let search: CGFloat = 24
        static let introGoogleBadge: CGFloat = 12
    }

    enum Layout {
        static let horizontalInset = Spacing.x16

        enum Onboarding {
            // On a 393x852 iPhone frame the safe-area top is 59pt. Figma puts
            // the 36pt navigation row at y=62 and the progress track at y=114.
            static let navigationTop: CGFloat = 3
            static let progressTopFromSafeArea = Spacing.x55
            static let contentTop = Spacing.x24

            static let titleSubtitleSpacing = Spacing.x8
            static let sectionSpacing = Spacing.x24
            static let rowSpacing = Spacing.x12
            static let searchToRowsSpacing = Spacing.x24
            static let companyColumnSpacing = Spacing.x12
            static let companyRowSpacing = Spacing.x12

            static let footerBottom = Spacing.x16
            static let footerTop = Spacing.x16
            static let questionHintBottom = Spacing.x31
        }

        enum Intro {
            static let logoTop = Spacing.x82
            static let logoToCard = Spacing.x43
            static let cardToTitle = Spacing.x48
            static let titleToDescription = Spacing.x12
            static let textHorizontal = Spacing.x32
            static let privacyToButton = Spacing.x47
        }

        enum LineHeight {
            static let title32: CGFloat = 38
            static let body16: CGFloat = 24
            static let body18: CGFloat = 27
        }
    }

    enum Animation {
        static let screenDuration: TimeInterval = 0.42
        static let progressDuration: TimeInterval = 0.36
        static let cardDuration: TimeInterval = 0.40
        static let cardStagger: TimeInterval = 0.045
        static let selectionDuration: TimeInterval = 0.22
    }
}

// MARK: - Typography
// One shared SF Pro access point for the whole app. This keeps size/weight visible
// at the call site, e.g. `.appBoldFont(size: 32)` exactly like the Figma spec.
extension UIFont {
    static func appRegularFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .regular)
    }

    static func appMediumFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    static func appSemiBoldFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    static func appBoldFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .bold)
    }

    static func appHeavyFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .heavy)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension UIView {
    func pinToEdges(of view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.topAnchor),
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
