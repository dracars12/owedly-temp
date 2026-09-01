import UIKit
import SnapKit

final class IntroViewController: UIViewController {
    var onFindMatches: (() -> Void)?

    private let logoView = OwedlyLogoView(frame: .zero)
    private let matchCard: MatchPreviewCard
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let privacyHint = HintView(
        symbolName: "checkmark.shield.fill",
        text: "Your answers stay private.",
        tint: DesignSystem.Color.brandGreen
    )
    private let primaryButton = PrimaryButton(frame: .zero)

    private var appliedCompactLayout: Bool?

    init() {
        let deadlineDate = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        matchCard = MatchPreviewCard(deadlineText: "Deadline \(formatter.string(from: deadlineDate))")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SoftBackgroundView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
    }

    private func configureUI() {
        titleLabel.numberOfLines = 2
        titleLabel.textColor = DesignSystem.Color.textPrimary

        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = DesignSystem.Color.textSecondary

        primaryButton.setTitle("Find My Matches", for: .normal)
        primaryButton.addTarget(self, action: #selector(findMatchesTapped), for: .touchUpInside)

        [logoView, matchCard, titleLabel, descriptionLabel, privacyHint, primaryButton].forEach(view.addSubview)
        applyResponsiveLayout(compact: false)
    }

    private func updateResponsiveLayoutIfNeeded() {
        guard view.bounds.height > 0 else { return }
        let compact = view.bounds.height <= 760
        guard appliedCompactLayout != compact else { return }
        applyResponsiveLayout(compact: compact)
    }

    private func applyResponsiveLayout(compact: Bool) {
        appliedCompactLayout = compact

        titleLabel.font = .appBoldFont(size: compact ? 29 : 32)
        titleLabel.setLineHeight(compact ? 34 : DesignSystem.Layout.LineHeight.title32)
        titleLabel.text = "Find money\nyou may be owed"
        titleLabel.setLineHeight(compact ? 34 : DesignSystem.Layout.LineHeight.title32)

        descriptionLabel.font = .appMediumFont(size: compact ? 16 : 18)
        descriptionLabel.text = "Companies settle cases every day.\nOwedly helps you discover settlements\nyou may qualify for."
        descriptionLabel.setLineHeight(compact ? 22 : DesignSystem.Layout.LineHeight.body18)

        logoView.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 22 : DesignSystem.Layout.Intro.logoTop)
            make.centerX.equalToSuperview()
            make.size.equalTo(compact ? CGSize(width: 170, height: 58) : DesignSystem.Size.logo)
        }
        matchCard.snp.remakeConstraints { make in
            make.top.equalTo(logoView.snp.bottom).offset(compact ? 18 : DesignSystem.Layout.Intro.logoToCard)
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            // MatchPreviewCard owns a fixed height. remakeConstraints removes its original
            // self-height constraint, so restore it here to prevent the card from collapsing.
            make.height.equalTo(DesignSystem.Size.introMatchCardHeight)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(matchCard.snp.bottom).offset(compact ? 24 : DesignSystem.Layout.Intro.cardToTitle)
            make.leading.equalToSuperview().offset(compact ? 26 : DesignSystem.Layout.Intro.textHorizontal)
            if compact {
                make.trailing.lessThanOrEqualToSuperview().inset(26)
            } else {
                make.width.equalTo(DesignSystem.Size.introTitleWidth)
            }
        }
        descriptionLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(compact ? 8 : DesignSystem.Layout.Intro.titleToDescription)
            make.leading.trailing.equalToSuperview().inset(compact ? 26 : DesignSystem.Layout.Intro.textHorizontal)
            make.bottom.lessThanOrEqualTo(privacyHint.snp.top).offset(compact ? -14 : -20)
        }
        primaryButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 10 : DesignSystem.Layout.Onboarding.footerBottom)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        privacyHint.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(primaryButton.snp.top).offset(compact ? -18 : -DesignSystem.Layout.Intro.privacyToButton)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
    }

    @objc private func findMatchesTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Ask for ATT on the very first introductory screen, before the user enters the
        // questionnaire. AppsFlyer is already initialized, but its first session remains gated
        // by AnalyticsCoordinator until this decision finishes. If ATT was already answered,
        // the completion is immediate and the onboarding opens normally.
        primaryButton.isEnabled = false
        AnalyticsCoordinator.shared.requestTrackingAuthorizationIfNeeded { [weak self] in
            guard let self else { return }
            self.primaryButton.isEnabled = true
            self.onFindMatches?()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}

private extension UILabel {
    func setLineHeight(_ lineHeight: CGFloat) {
        guard let text else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font as Any,
                .foregroundColor: textColor as Any,
                .paragraphStyle: paragraph
            ]
        )
    }
}
