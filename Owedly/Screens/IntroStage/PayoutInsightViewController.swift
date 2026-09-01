import UIKit
import SnapKit

final class PayoutInsightViewController: UIViewController {
    var onContinue: (() -> Void)?

    private let bankIcon = UIImageView()
    private let readyLabel = UILabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let insightCard = MaterialSurfaceView(
        borderColor: DesignSystem.Color.brandGreen,
        tintColor: DesignSystem.Color.selectedCardFill
    )
    private let primaryButton = PrimaryButton(frame: .zero)
    private let footnoteLabel = UILabel()

    private let magnifier = UIImageView(image: UIImage(systemName: "exclamationmark.magnifyingglass"))
    private let cardTitle = UILabel()
    private let cardBody = UILabel()
    private var appliedCompactLayout: Bool?

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
    }

    private func configureUI() {
        bankIcon.image = UIImage(systemName: "dollarsign.bank.building") ?? UIImage(systemName: "banknote")
        bankIcon.tintColor = DesignSystem.Color.brandGreen
        bankIcon.contentMode = .scaleAspectFit

        readyLabel.applyAppText(
            "YOUR MATCHES ARE READY",
            font: .appBoldFont(size: 14),
            color: DesignSystem.Color.brandGreen,
            lineHeight: 21,
            alignment: .center
        )

        magnifier.tintColor = DesignSystem.Color.brandGreen
        magnifier.contentMode = .scaleAspectFit

        cardTitle.applyAppText(
            "Your personalized\nmatches are ready",
            font: .appSemiBoldFont(size: 24),
            color: DesignSystem.Color.textPrimary,
            lineHeight: 29
        )
        cardBody.applyAppText(
            "Review opportunities relevant\nto your answers",
            font: .appMediumFont(size: 16),
            color: DesignSystem.Color.textSecondary,
            lineHeight: 19
        )

        insightCard.addSubview(magnifier)
        insightCard.addSubview(cardTitle)
        insightCard.addSubview(cardBody)
        magnifier.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(17)
            make.top.equalToSuperview().offset(17)
            make.size.equalTo(57)
        }
        cardTitle.snp.makeConstraints { make in
            make.leading.equalTo(magnifier.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(12)
            make.top.equalToSuperview().offset(17)
        }
        cardBody.snp.makeConstraints { make in
            make.leading.trailing.equalTo(cardTitle)
            make.top.equalTo(cardTitle.snp.bottom).offset(8)
            make.bottom.lessThanOrEqualToSuperview().inset(17)
        }

        primaryButton.setTitle("Continue", for: .normal)
        primaryButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        footnoteLabel.applyAppText(
            "*Based on internal Owedly data from 2025–2026.\nIndividual outcomes vary. Eligibility and payment\nare not guaranteed.",
            font: .appMediumFont(size: 13),
            color: DesignSystem.Color.textSecondary,
            lineHeight: 17,
            alignment: .center
        )

        [bankIcon, readyLabel, headlineLabel, bodyLabel, insightCard, primaryButton, footnoteLabel].forEach(view.addSubview)
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

        bankIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: compact ? 56 : 66, weight: .regular)
        magnifier.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: compact ? 42 : 46, weight: .regular)

        let headlineSize: CGFloat = compact ? 26 : 29
        let headlineLineHeight: CGFloat = compact ? 31 : 34
        let headlineFont = UIFont.appBoldFont(size: headlineSize)
        let headline = NSMutableAttributedString(
            string: "Members receive ",
            attributes: [.font: headlineFont, .foregroundColor: DesignSystem.Color.textPrimary]
        )
        headline.append(NSAttributedString(
            string: "$500",
            attributes: [.font: UIFont.appHeavyFont(size: headlineSize), .foregroundColor: DesignSystem.Color.brandGreen]
        ))
        headline.append(NSAttributedString(
            string: "\non average in their\nfirst year*",
            attributes: [.font: headlineFont, .foregroundColor: DesignSystem.Color.textPrimary]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = headlineLineHeight
        paragraph.maximumLineHeight = headlineLineHeight
        headline.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: headline.length))
        headlineLabel.attributedText = headline
        headlineLabel.numberOfLines = 3
        headlineLabel.textAlignment = .center

        bodyLabel.applyAppText(
            "Relevant settlements can be easy to miss.\nOwedly helps you find potential matches\nand stay ahead of filing deadlines.",
            font: .appMediumFont(size: compact ? 15 : 17),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 20 : 22,
            alignment: .center
        )

        bankIcon.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 12 : 24)
            make.centerX.equalToSuperview()
            make.size.equalTo(compact ? CGSize(width: 60, height: 60) : CGSize(width: 68, height: 68))
        }
        readyLabel.snp.remakeConstraints { make in
            make.top.equalTo(bankIcon.snp.bottom).offset(compact ? 6 : 8)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        headlineLabel.snp.remakeConstraints { make in
            make.top.equalTo(readyLabel.snp.bottom).offset(compact ? 6 : 8)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        bodyLabel.snp.remakeConstraints { make in
            make.top.equalTo(headlineLabel.snp.bottom).offset(compact ? 8 : 16)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        insightCard.snp.remakeConstraints { make in
            make.top.equalTo(bodyLabel.snp.bottom).offset(compact ? 14 : 28)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(compact ? 130 : 138)
            make.bottom.lessThanOrEqualTo(primaryButton.snp.top).offset(-12)
        }
        primaryButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 72 : 84)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        footnoteLabel.snp.remakeConstraints { make in
            make.top.equalTo(primaryButton.snp.bottom).offset(compact ? 10 : 18)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.bottom).inset(6)
        }
    }

    @objc private func continueTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onContinue?()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
