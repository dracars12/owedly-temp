import UIKit
import SnapKit

final class PaymentSuccessViewController: UIViewController {
    var onViewMatches: (() -> Void)?

    private let glyph = LargeSuccessGlyphView(size: 96)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let unlockedLabel = UILabel()
    private let featureCard = MaterialSurfaceView()
    private let privacyHint = HintView(
        symbolName: "checkmark.shield.fill",
        text: "Your answers and claim activity stay private.",
        tint: DesignSystem.Color.brandGreen
    )
    private let primaryButton = PrimaryButton(frame: .zero)
    private let noteLabel = UILabel()

    private var appliedLayoutSignature: Int?

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
        unlockedLabel.applyAppText(
            "Premium unlocked",
            font: .appBoldFont(size: 18),
            color: DesignSystem.Color.textPrimary,
            lineHeight: DesignSystem.Layout.LineHeight.body18,
            alignment: .center
        )

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        ["All potential matches", "Deadline alerts", "Claim tracking"].forEach { title in
            let row = UIView()
            let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            icon.tintColor = DesignSystem.Color.brandGreen
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            let label = UILabel()
            label.text = title
            label.font = .appRegularFont(size: 16)
            label.textColor = DesignSystem.Color.textPrimary
            row.addSubview(icon)
            row.addSubview(label)
            icon.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(24)
                make.centerY.equalToSuperview()
                make.size.equalTo(24)
            }
            label.snp.makeConstraints { make in
                make.leading.equalTo(icon.snp.trailing).offset(8)
                make.trailing.lessThanOrEqualToSuperview().inset(16)
                make.centerY.equalToSuperview()
            }
            row.snp.makeConstraints { $0.height.equalTo(49) }
            stack.addArrangedSubview(row)
        }
        for row in stack.arrangedSubviews.dropLast() {
            let line = UIView()
            line.backgroundColor = DesignSystem.Color.cardBorder
            row.addSubview(line)
            line.snp.makeConstraints { make in
                make.leading.trailing.bottom.equalToSuperview()
                make.height.equalTo(1.0 / UIScreen.main.scale)
            }
        }
        featureCard.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }

        primaryButton.setTitle("View my matches", for: .normal)
        primaryButton.addTarget(self, action: #selector(viewMatchesTapped), for: .touchUpInside)
        noteLabel.applyAppText(
            "You can manage your subscription in App Store\nsettings.",
            font: .appMediumFont(size: 14),
            color: DesignSystem.Color.textSecondary,
            lineHeight: 17,
            alignment: .center
        )

        [glyph, titleLabel, subtitleLabel, unlockedLabel, featureCard, privacyHint, primaryButton, noteLabel].forEach(view.addSubview)
        applyResponsiveLayout(compact: false, smallPhone: false)
    }

    private func updateResponsiveLayoutIfNeeded() {
        guard view.bounds.height > 0 else { return }
        let signature = view.bounds.height <= 760 ? 2 : (view.bounds.height <= 812 ? 1 : 0)
        guard appliedLayoutSignature != signature else { return }
        applyResponsiveLayout(compact: signature == 2, smallPhone: signature >= 1)
    }

    private func applyResponsiveLayout(compact: Bool, smallPhone: Bool) {
        appliedLayoutSignature = compact ? 2 : (smallPhone ? 1 : 0)

        titleLabel.applyAppText(
            "You’re all set",
            font: .appBoldFont(size: compact ? 28 : 32),
            color: DesignSystem.Color.textPrimary,
            lineHeight: compact ? 33 : DesignSystem.Layout.LineHeight.title32,
            alignment: .center
        )
        subtitleLabel.applyAppText(
            "Your Owedly Premium access is now active",
            font: .appMediumFont(size: compact ? 16 : 18),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 23 : DesignSystem.Layout.LineHeight.body18,
            alignment: .center
        )

        glyph.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 12 : (smallPhone ? 52 : 80))
            make.centerX.equalToSuperview()
            make.size.equalTo(115)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(glyph.snp.bottom).offset(compact ? 14 : 36)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        subtitleLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(compact ? 6 : 12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        unlockedLabel.snp.remakeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(compact ? 14 : 24)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        featureCard.snp.remakeConstraints { make in
            make.top.equalTo(unlockedLabel.snp.bottom).offset(compact ? 8 : 12)
            make.centerX.equalToSuperview()
            make.width.equalTo(241)
            make.height.equalTo(148)
        }
        privacyHint.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(featureCard.snp.bottom).offset(compact ? 14 : 45)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
            make.bottom.lessThanOrEqualTo(primaryButton.snp.top).offset(-12)
        }
        primaryButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 58 : 65)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        noteLabel.snp.remakeConstraints { make in
            make.top.equalTo(primaryButton.snp.bottom).offset(compact ? 10 : 16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.bottom).inset(6)
        }
    }

    @objc private func viewMatchesTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onViewMatches?()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
