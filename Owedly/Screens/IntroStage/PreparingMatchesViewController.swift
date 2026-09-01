import UIKit
import SnapKit

final class PreparingMatchesViewController: UIViewController {
    var onFinished: ((SettlementScanResult) -> Void)?

    private let glyph = LargeSuccessGlyphView(size: 96)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let processCard = ProcessCardView()
    private let privacyHint = HintView(
        symbolName: "checkmark.shield.fill",
        text: "Your answers stay private.",
        tint: DesignSystem.Color.brandGreen
    )

    private var didStart = false
    private var scanTask: Task<SettlementScanResult, Never>?
    private var websiteScanProgress: Double = 0
    private var appliedLayoutSignature: Int?

    override func loadView() {
        view = SoftBackgroundView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Start the real iPhone catalog scan immediately so network/cache + HTML parsing overlap
        // the first two visual stages. A successful live scan is cached locally; if it fails,
        // SettlementDataManager falls back to the local cache and finally to bundled demo data.
        scanTask = makeScanTask()
        configureUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startFlowIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
    }

    private func configureUI() {
        [glyph, titleLabel, subtitleLabel, processCard, privacyHint].forEach(view.addSubview)
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
            "Preparing your matches",
            font: .appBoldFont(size: compact ? 28 : 32),
            color: DesignSystem.Color.textPrimary,
            lineHeight: compact ? 33 : DesignSystem.Layout.LineHeight.title32,
            alignment: .center
        )
        subtitleLabel.applyAppText(
            "We’re comparing your answers with\nrelevant settlements",
            font: .appMediumFont(size: compact ? 16 : 18),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 23 : DesignSystem.Layout.LineHeight.body18,
            alignment: .center
        )

        glyph.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 12 : (smallPhone ? 42 : 80))
            make.centerX.equalToSuperview()
            // LargeSuccessGlyphView originally installs this on itself; remakeConstraints
            // removes it, which made the image draw outside a zero-height view on iPad.
            make.size.equalTo(115)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(glyph.snp.bottom).offset(compact ? 10 : 36)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        subtitleLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(compact ? 8 : 12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        processCard.snp.remakeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(compact ? 10 : 24)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        privacyHint.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(processCard.snp.bottom).offset(compact ? 10 : 31)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.bottom).inset(12)
        }
    }

    private func startFlowIfNeeded() {
        guard !didStart else { return }
        didStart = true

        // The fetch/scan was already kicked off in viewDidLoad so it overlaps the first
        // loader instead of waiting for the push transition to finish.
        if scanTask == nil {
            scanTask = makeScanTask()
        }

        let row1 = processCard.appendRow(title: "Companies and services", animated: true)
        processCard.addProgressRowIfNeeded(animated: true)
        processCard.progressRow.setProgress(0.18, animated: false)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            row1.setState(.complete, animated: true)
            self.processCard.progressRow.setProgress(0.34, animated: true)

            let row2 = self.processCard.appendRow(title: "State and eligibility periods", animated: true)
            self.view.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            row2.setState(.complete, animated: true)
            self.processCard.progressRow.setProgress(0.66, animated: true)

            let row3 = self.processCard.appendRow(title: "Settlement categories", animated: true)
            self.processCard.progressRow.setProgress(max(0.78, 0.78 + self.websiteScanProgress * 0.17), animated: true)
            self.view.layoutIfNeeded()

            async let minimumThirdStage: Void = Task.sleep(nanoseconds: 1_000_000_000)
            let result = await self.scanTask?.value ?? SettlementScanner.shared.scan([])
            _ = try? await minimumThirdStage
            await NotificationManager.shared.refreshIfAlreadyAuthorized(scanResult: result)

            // Do not hold a separate final “Done” state. As soon as the minimum third-stage
            // time and the real scan are both complete, finish the progress and move on.
            row3.setState(.complete, animated: false)
            self.processCard.progressRow.setProgress(1.0, animated: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.onFinished?(result)
        }
    }

    private func makeScanTask() -> Task<SettlementScanResult, Never> {
        Task { [weak self] in
            await SettlementScanner.shared.loadAndScan(
                refreshPolicy: .preferFreshCache,
                progress: { progress in
                    Task { @MainActor [weak self] in
                        self?.websiteScanProgress = max(self?.websiteScanProgress ?? 0, progress)
                        self?.applyWebsiteProgressIfVisible()
                    }
                }
            )
        }
    }

    @MainActor
    private func applyWebsiteProgressIfVisible() {
        guard processCard.progressRow.superview != nil else { return }
        // The first 78% belongs to the onboarding/profile stages. The real website scan
        // owns the remaining visual range and can continue moving while a slow page loads.
        let mapped = 0.78 + min(max(websiteScanProgress, 0), 1) * 0.17
        processCard.progressRow.setProgress(mapped, animated: true)
    }

    deinit {
        scanTask?.cancel()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
