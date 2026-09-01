import UIKit
import SnapKit

final class PaywallViewController: UIViewController {
    var onClose: (() -> Void)?
    var onPurchaseSuccess: (() -> Void)?
    var onRestoreSuccess: (() -> Void)?

    private let scanResult: SettlementScanResult
    private let purchaseManager: PurchaseManager
    private let restoreButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let markView = UIImageView(image: UIImage(named: "owedly_mark"))
    private let readyLabel = UILabel()
    private let headlineLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let deadlineBadge = MaterialSurfaceView(cornerRadius: 12, tintColor: DesignSystem.Color.selectedCardFill)
    private let annualCard = SubscriptionPlanCard(plan: .annual)
    private let weeklyCard = SubscriptionPlanCard(plan: .weekly)
    private let renewalLabel = UILabel()
    private let purchaseButton = ShimmerPrimaryButton(frame: .zero)
    private let termsButton = UIButton(type: .system)
    private let privacyButton = UIButton(type: .system)

    private var selectedPlan: PurchasePlan = .annual
    private var productsLoaded = false
    private var isProcessing = false
    private var hasLoggedPresentation = false
    private var appliedLayoutSignature: Int?

    init(scanResult: SettlementScanResult, purchaseManager: PurchaseManager = .shared) {
        self.scanResult = scanResult
        self.purchaseManager = purchaseManager
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storefrontDidChange),
            name: .owedlyPurchaseStorefrontDidChange,
            object: nil
        )

        let hasCachedProducts = applyCachedPlacement(animated: false)
        if !hasCachedProducts {
            setProductContentHidden(true, animated: false)
        }
        loadProducts(showFailureAlert: !hasCachedProducts)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        purchaseButton.startShimmering()
        logPresentationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        purchaseButton.stopShimmering()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureUI() {
        restoreButton.setTitle("Restore", for: .normal)
        restoreButton.setTitleColor(DesignSystem.Color.textSecondary, for: .normal)
        restoreButton.titleLabel?.font = .appMediumFont(size: 14)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        let closeSymbol = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeSymbol), for: .normal)
        closeButton.tintColor = UIColor.black.withAlphaComponent(0.48)
        closeButton.backgroundColor = .white
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        markView.contentMode = .scaleAspectFit
        readyLabel.applyAppText(
            "YOUR MATCHES ARE READY",
            font: .appBoldFont(size: 14),
            color: DesignSystem.Color.brandGreen,
            lineHeight: 21,
            alignment: .center
        )

        let calendarIcon = UIImageView(image: UIImage(systemName: "calendar"))
        calendarIcon.tintColor = DesignSystem.Color.brandGreen
        calendarIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let deadlineLabel = UILabel()
        let days = scanResult.nearestDeadlineDays ?? Int.random(in: 10...22)
        deadlineLabel.text = "Next deadline in \(days) days"
        deadlineLabel.font = .appSemiBoldFont(size: 16)
        deadlineLabel.textColor = DesignSystem.Color.textPrimary
        deadlineBadge.addSubview(calendarIcon)
        deadlineBadge.addSubview(deadlineLabel)
        calendarIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        deadlineLabel.snp.makeConstraints { make in
            make.leading.equalTo(calendarIcon.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
        deadlineBadge.snp.makeConstraints { $0.height.equalTo(42) }

        annualCard.isSelected = true
        weeklyCard.isSelected = false
        annualCard.addTarget(self, action: #selector(planTapped(_:)), for: .touchUpInside)
        weeklyCard.addTarget(self, action: #selector(planTapped(_:)), for: .touchUpInside)

        renewalLabel.applyAppText(
            "Subscription renews automatically. Cancel anytime.",
            font: .appMediumFont(size: 14),
            color: DesignSystem.Color.textSecondary,
            lineHeight: 17,
            alignment: .center
        )
        purchaseButton.setTitle("Loading plans…", for: .normal)
        purchaseButton.isEnabled = false
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)

        [termsButton, privacyButton].forEach {
            $0.setTitleColor(DesignSystem.Color.textSecondary, for: .normal)
            $0.titleLabel?.font = .appMediumFont(size: 12)
        }
        termsButton.setTitle("Terms of Use", for: .normal)
        privacyButton.setTitle("Privacy Policy", for: .normal)
        termsButton.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)
        privacyButton.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)

        [restoreButton, closeButton, markView, readyLabel, headlineLabel, descriptionLabel, deadlineBadge, annualCard, weeklyCard, renewalLabel, purchaseButton, termsButton, privacyButton].forEach(view.addSubview)
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

        let count = scanResult.potentialMatches.count
        let headlineSize: CGFloat = compact ? 34 : 42
        let headlineLineHeight: CGFloat = compact ? 40 : 49
        let number = NSMutableAttributedString(
            string: "\(count)",
            attributes: [.font: UIFont.appHeavyFont(size: headlineSize), .foregroundColor: DesignSystem.Color.brandGreen]
        )
        number.append(NSAttributedString(
            string: " potential\nmatches found",
            attributes: [.font: UIFont.appSemiBoldFont(size: headlineSize), .foregroundColor: DesignSystem.Color.textPrimary]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = headlineLineHeight
        paragraph.maximumLineHeight = headlineLineHeight
        number.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: number.length))
        headlineLabel.attributedText = number
        headlineLabel.numberOfLines = 2
        headlineLabel.textAlignment = .center

        descriptionLabel.applyAppText(
            "Based on your answers, these settlements\nmay be relevant to you.",
            font: .appMediumFont(size: compact ? 15 : (smallPhone ? 16 : 18)),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 20 : (smallPhone ? 23 : DesignSystem.Layout.LineHeight.body18),
            alignment: .center
        )

        restoreButton.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(3)
            make.height.equalTo(36)
        }
        closeButton.snp.remakeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(3)
            make.size.equalTo(36)
        }
        markView.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 8 : 16)
            make.centerX.equalToSuperview()
            make.size.equalTo(44)
        }
        readyLabel.snp.remakeConstraints { make in
            make.top.equalTo(markView.snp.bottom).offset(compact ? 6 : 12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        headlineLabel.snp.remakeConstraints { make in
            make.top.equalTo(readyLabel.snp.bottom).offset(compact ? 8 : 16)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        descriptionLabel.snp.remakeConstraints { make in
            make.top.equalTo(headlineLabel.snp.bottom).offset(compact ? 8 : 14)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        deadlineBadge.snp.remakeConstraints { make in
            make.top.equalTo(descriptionLabel.snp.bottom).offset(compact ? 10 : 24)
            make.centerX.equalToSuperview()
            make.height.equalTo(42)
        }
        annualCard.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(deadlineBadge.snp.bottom).offset(compact ? 12 : 52)
            make.height.equalTo(106)
        }
        weeklyCard.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(annualCard.snp.bottom).offset(compact ? 8 : 16)
            make.height.equalTo(84)
            make.bottom.lessThanOrEqualTo(renewalLabel.snp.top).offset(-10)
        }
        privacyButton.snp.remakeConstraints { make in
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(2)
            make.centerX.equalToSuperview().offset(63)
            make.height.equalTo(24)
        }
        termsButton.snp.remakeConstraints { make in
            make.centerY.equalTo(privacyButton)
            make.centerX.equalToSuperview().offset(-63)
            make.height.equalTo(24)
        }
        purchaseButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(termsButton.snp.top).offset(compact ? -6 : -10)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        renewalLabel.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(purchaseButton.snp.top).offset(compact ? -8 : -16)
        }
    }

    private func loadProducts(showFailureAlert: Bool) {
        guard !isProcessing else { return }
        let hadRenderableProducts = productsLoaded

        if !hadRenderableProducts {
            annualCard.setLoading()
            weeklyCard.setLoading()
            purchaseButton.setTitle("Loading plans…", for: .normal)
            purchaseButton.isEnabled = false
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let placement = try await self.purchaseManager.loadPlacement(.defaultPaywall)
                guard self.applyPlacement(placement, animated: self.viewIfLoaded?.window != nil) else {
                    throw PaywallLoadingError.noProducts
                }
                self.logPresentationIfNeeded()
            } catch {
                // If we already rendered persisted/live StoreKit metadata, never replace correct
                // prices with a loading/error placeholder just because a foreground refresh failed.
                if hadRenderableProducts || self.productsLoaded {
                    print("[Adapty] Keeping cached paywall products after refresh failure: \(error.localizedDescription)")
                    return
                }

                self.annualCard.setUnavailable()
                self.weeklyCard.setUnavailable()
                self.productsLoaded = false
                self.purchaseButton.setTitle("Retry plans", for: .normal)
                self.purchaseButton.isEnabled = true
                self.setProductContentHidden(false, animated: true)
                if showFailureAlert {
                    self.showAlert(
                        title: "Plans unavailable",
                        message: "We couldn’t load the current App Store plans. Check your connection and try again.\n\n\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @discardableResult
    private func applyCachedPlacement(animated: Bool) -> Bool {
        guard let placement = purchaseManager.cachedPlacement(.defaultPaywall) else { return false }
        return applyPlacement(placement, animated: animated)
    }

    @discardableResult
    private func applyPlacement(_ placement: PurchasePlacementInfo, animated: Bool) -> Bool {
        let annual = placement.products[.annual]
        let weekly = placement.products[.weekly]
        guard annual != nil || weekly != nil else { return false }

        if let annual { annualCard.configure(with: annual) } else { annualCard.setUnavailable() }
        if let weekly { weeklyCard.configure(with: weekly) } else { weeklyCard.setUnavailable() }

        let preferredPlan: PurchasePlan
        if placement.products[selectedPlan] != nil {
            preferredPlan = selectedPlan
        } else if annual != nil {
            preferredPlan = .annual
        } else {
            preferredPlan = .weekly
        }

        productsLoaded = true
        select(preferredPlan, haptic: false)
        purchaseButton.setTitle("Unlock my matches", for: .normal)
        purchaseButton.isEnabled = !isProcessing
        setProductContentHidden(false, animated: animated)
        return true
    }

    private func setProductContentHidden(_ hidden: Bool, animated: Bool) {
        let views: [UIView] = [annualCard, weeklyCard, renewalLabel, purchaseButton]
        if hidden {
            views.forEach { $0.isHidden = true }
            return
        }

        let wasHidden = views.contains(where: { $0.isHidden })
        views.forEach { $0.isHidden = false }
        guard animated, wasHidden else { return }
        views.forEach { $0.alpha = 0 }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            views.forEach { $0.alpha = 1 }
        }
    }

    @objc private func storefrontDidChange() {
        _ = applyCachedPlacement(animated: viewIfLoaded?.window != nil)
        logPresentationIfNeeded()
    }

    private func logPresentationIfNeeded() {
        guard productsLoaded, viewIfLoaded?.window != nil, !hasLoggedPresentation else { return }
        hasLoggedPresentation = true
        Task { [purchaseManager] in
            await purchaseManager.logPresentation(for: .defaultPaywall)
        }
    }

    private func select(_ plan: PurchasePlan, haptic: Bool) {
        let card = plan == .annual ? annualCard : weeklyCard
        guard card.isEnabled else { return }
        selectedPlan = plan
        annualCard.isSelected = plan == .annual
        weeklyCard.isSelected = plan == .weekly
        if haptic { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func setProcessing(_ processing: Bool, buttonTitle: String? = nil) {
        isProcessing = processing
        restoreButton.isEnabled = !processing
        closeButton.isEnabled = !processing
        annualCard.isEnabled = !processing && productsLoaded && annualCard.alpha > 0.7
        weeklyCard.isEnabled = !processing && productsLoaded && weeklyCard.alpha > 0.7
        purchaseButton.isEnabled = !processing
        if let buttonTitle { purchaseButton.setTitle(buttonTitle, for: .normal) }
        restoreButton.alpha = processing ? 0.55 : 1
    }

    @objc private func planTapped(_ sender: SubscriptionPlanCard) {
        guard sender.isEnabled, !isProcessing else { return }
        select(sender.plan, haptic: true)
    }

    @objc private func closeTapped() {
        guard !isProcessing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onClose?()
    }

    @objc private func restoreTapped() {
        guard !isProcessing else { return }
        setProcessing(true, buttonTitle: "Restoring…")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.purchaseManager.restorePurchases()
            self.setProcessing(false, buttonTitle: self.productsLoaded ? "Unlock my matches" : "Retry plans")

            switch result {
            case .restored:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                (self.onRestoreSuccess ?? self.onPurchaseSuccess)?()
            case .noActiveSubscription:
                self.showAlert(
                    title: "Nothing to restore",
                    message: "No active Owedly subscription was found for this Apple ID."
                )
            case let .failed(message):
                self.showAlert(title: "Restore failed", message: message)
            }
        }
    }

    @objc private func termsTapped() { AppLinks.open(AppLinks.terms) }

    @objc private func privacyTapped() { AppLinks.open(AppLinks.privacy) }

    @objc private func purchaseTapped() {
        guard !isProcessing else { return }
        guard productsLoaded else {
            loadProducts(showFailureAlert: true)
            return
        }

        setProcessing(true, buttonTitle: "Processing…")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.purchaseManager.purchase(self.selectedPlan, placement: .defaultPaywall)
            self.setProcessing(false, buttonTitle: "Unlock my matches")

            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.onPurchaseSuccess?()
            case .cancelled:
                break
            case .pending:
                self.showAlert(
                    title: "Purchase pending",
                    message: "Apple is still processing this purchase. Premium will unlock automatically as soon as it is approved."
                )
            case let .failed(message):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.showAlert(title: "Purchase failed", message: message)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}

private enum PaywallLoadingError: LocalizedError {
    case noProducts

    var errorDescription: String? {
        "The default Adapty placement did not return a weekly or annual subscription."
    }
}
