import UIKit
import SnapKit

final class NotificationsViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let preview = FauxNotificationView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let alertsRow = MaterialSurfaceView()
    private let deadlinesRow = MaterialSurfaceView()
    private let notNowButton = UIButton(type: .system)
    private let finishButton = PrimaryButton(frame: .zero)

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
        configureFeatureRow(alertsRow, symbol: "bell", tint: DesignSystem.Color.brandGreen, title: "New settlement alerts")
        configureFeatureRow(deadlinesRow, symbol: "calendar", tint: DesignSystem.Color.iconBlue, title: "Deadline reminders")

        notNowButton.setTitle("Not Now", for: .normal)
        notNowButton.setTitleColor(DesignSystem.Color.brandGreen, for: .normal)
        notNowButton.titleLabel?.font = .appSemiBoldFont(size: 16)
        notNowButton.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
        finishButton.setTitle("Finish", for: .normal)
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)

        [preview, titleLabel, subtitleLabel, alertsRow, deadlinesRow, notNowButton, finishButton].forEach(view.addSubview)
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

        titleLabel.applyAppText(
            "Don’t miss\nnew matches",
            font: .appBoldFont(size: compact ? 28 : 32),
            color: DesignSystem.Color.textPrimary,
            lineHeight: compact ? 33 : DesignSystem.Layout.LineHeight.title32,
            alignment: .center
        )
        subtitleLabel.applyAppText(
            "Get notified when relevant\nsettlements open or deadlines are\napproaching.",
            font: .appMediumFont(size: compact ? 15 : 18),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 21 : DesignSystem.Layout.LineHeight.body18,
            alignment: .center
        )

        preview.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 16 : 47)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(66)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(preview.snp.bottom).offset(compact ? 24 : 61)
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(317)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        subtitleLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(compact ? 6 : 12)
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(317)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        alertsRow.snp.remakeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(compact ? 18 : 36)
            make.centerX.equalToSuperview()
            make.width.equalTo(263)
            make.height.equalTo(56)
        }
        deadlinesRow.snp.remakeConstraints { make in
            make.top.equalTo(alertsRow.snp.bottom).offset(compact ? 10 : 12)
            make.centerX.width.height.equalTo(alertsRow)
            make.bottom.lessThanOrEqualTo(notNowButton.snp.top).offset(-12)
        }
        finishButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 10 : 16)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        notNowButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(finishButton.snp.top).offset(compact ? -8 : -10)
            make.height.equalTo(compact ? 50 : 56)
        }
    }

    private func configureFeatureRow(_ row: MaterialSurfaceView, symbol: String, tint: UIColor, title: String) {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let label = UILabel()
        label.text = title
        label.font = .appRegularFont(size: 16)
        label.textColor = DesignSystem.Color.textPrimary
        row.addSubview(icon)
        row.addSubview(label)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(title == "New settlement alerts" ? 32.5 : 41.5)
            make.centerY.equalToSuperview()
            make.size.equalTo(26)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }
    }

    @objc private func notNowTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onFinished?()
    }

    @objc private func finishTapped() {
        finishButton.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await NotificationManager.shared.requestAuthorizationAndActivate()
            self.finishButton.isEnabled = true
            self.onFinished?()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
