import UIKit
import SnapKit
import SPConfetti

final class LimitedOfferViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let purchaseManager: PurchaseManager
    private let restoreButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let giftIcon = UIImageView(image: UIImage(systemName: "gift"))
    private let badgeLabel = UILabel()
    private let discountView = DiscountShimmerView()
    private let subtitleLabel = UILabel()
    private let timerPill = MaterialSurfaceView()
    private let timerLabel = UILabel()
    private let planCard = UIView()
    private let annualLabel = UILabel()
    private let oldPriceLabel = UILabel()
    private let priceLabel = UILabel()
    private let weeklyLabel = UILabel()
    private let includedLabel = UILabel()
    private let renewalLabel = UILabel()
    private let purchaseButton = ShimmerPrimaryButton(frame: .zero)

    private var timer: Timer?
    private var offerLoaded = false
    private var isProcessing = false
    private var hasLoggedPresentation = false
    private var appliedCompactLayout: Bool?

    init(purchaseManager: PurchaseManager = .shared) {
        self.purchaseManager = purchaseManager
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        updateTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storefrontDidChange),
            name: .owedlyPurchaseStorefrontDidChange,
            object: nil
        )

        let hasCachedOffer = applyCachedOffer(animated: false)
        if !hasCachedOffer {
            setOfferContentHidden(true, animated: false)
        }
        loadOffer(showFailureAlert: !hasCachedOffer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        purchaseButton.startShimmering()
        discountView.startShimmering()
        SPConfetti.startAnimating(.fullWidthToDown, particles: [.triangle, .arc, .circle], duration: 2.4)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updateTimer() }
        }
        logPresentationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
        purchaseButton.stopShimmering()
        discountView.stopShimmering()
        SPConfetti.stopAnimating()
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

        giftIcon.tintColor = DesignSystem.Color.brandGreen
        giftIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46, weight: .medium)
        giftIcon.contentMode = .scaleAspectFit

        badgeLabel.text = "LIMITED-TIME OFFER"
        badgeLabel.font = .appBoldFont(size: 14)
        badgeLabel.textColor = DesignSystem.Color.brandGreen
        badgeLabel.textAlignment = .center

        subtitleLabel.text = "Keep discovering potential matches all year."
        subtitleLabel.font = .appMediumFont(size: 16)
        subtitleLabel.textColor = DesignSystem.Color.textSecondary
        subtitleLabel.textAlignment = .center

        let clock = UIImageView(image: UIImage(systemName: "clock"))
        clock.tintColor = DesignSystem.Color.textSecondary
        clock.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let prefix = UILabel()
        prefix.text = "Offer ends in"
        prefix.font = .appRegularFont(size: 18)
        prefix.textColor = .black
        timerLabel.font = .appSemiBoldFont(size: 18)
        timerLabel.textColor = DesignSystem.Color.brandGreen
        timerPill.layer.cornerRadius = 25
        timerPill.addSubview(clock)
        timerPill.addSubview(prefix)
        timerPill.addSubview(timerLabel)
        clock.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        prefix.snp.makeConstraints { make in
            make.leading.equalTo(clock.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
        }
        timerLabel.snp.makeConstraints { make in
            make.leading.equalTo(prefix.snp.trailing).offset(4)
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        timerPill.snp.makeConstraints { $0.height.equalTo(50) }

        planCard.backgroundColor = DesignSystem.Color.selectedCardFill
        planCard.layer.cornerRadius = 16
        planCard.layer.borderWidth = 1
        planCard.layer.borderColor = DesignSystem.Color.brandGreen.cgColor

        annualLabel.text = "Annual Access"
        annualLabel.font = .appBoldFont(size: 18)
        annualLabel.textColor = .black
        annualLabel.adjustsFontSizeToFitWidth = true
        annualLabel.minimumScaleFactor = 0.82

        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = DesignSystem.Color.brandGreen
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        oldPriceLabel.attributedText = struckPrice("Loading…")
        priceLabel.attributedText = priceText(price: "Loading…", period: "")
        weeklyLabel.text = "Loading current App Store price"
        weeklyLabel.font = .appMediumFont(size: 16)
        weeklyLabel.textColor = DesignSystem.Color.textSecondary

        [annualLabel, check, oldPriceLabel, priceLabel, weeklyLabel].forEach(planCard.addSubview)
        annualLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(check.snp.leading).offset(-8)
        }
        check.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().inset(12)
            make.size.equalTo(24)
        }
        oldPriceLabel.snp.makeConstraints { make in
            make.leading.equalTo(annualLabel)
            make.top.equalTo(annualLabel.snp.bottom).offset(8)
        }
        priceLabel.snp.makeConstraints { make in
            make.leading.equalTo(annualLabel)
            make.top.equalTo(oldPriceLabel.snp.bottom).offset(3)
        }
        weeklyLabel.snp.makeConstraints { make in
            make.leading.equalTo(annualLabel)
            make.top.equalTo(priceLabel.snp.bottom).offset(3)
        }
        planCard.snp.makeConstraints { $0.height.equalTo(164) }

        includedLabel.text = "✓  Full premium access included"
        includedLabel.font = .appMediumFont(size: 16)
        includedLabel.textColor = DesignSystem.Color.textSecondary
        includedLabel.textAlignment = .center

        renewalLabel.text = "Subscription renews automatically. Cancel anytime."
        renewalLabel.font = .appMediumFont(size: 14)
        renewalLabel.textColor = DesignSystem.Color.textSecondary
        renewalLabel.textAlignment = .center

        purchaseButton.setTitle("Loading offer…", for: .normal)
        purchaseButton.isEnabled = false
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)

        [restoreButton, closeButton, giftIcon, badgeLabel, discountView, subtitleLabel, timerPill, planCard, includedLabel, renewalLabel, purchaseButton].forEach(view.addSubview)

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

        restoreButton.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(3)
            make.leading.equalToSuperview().offset(16)
            make.height.equalTo(36)
        }
        closeButton.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(3)
            make.trailing.equalToSuperview().inset(16)
            make.size.equalTo(36)
        }
        giftIcon.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 10 : 28)
            make.centerX.equalToSuperview()
            make.size.equalTo(compact ? 48 : 54)
        }
        badgeLabel.snp.remakeConstraints { make in
            make.top.equalTo(giftIcon.snp.bottom).offset(compact ? 8 : 15)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        discountView.snp.remakeConstraints { make in
            make.top.equalTo(badgeLabel.snp.bottom).offset(compact ? 10 : 16)
            make.centerX.equalToSuperview()
            make.height.equalTo(98)
            make.leading.trailing.equalToSuperview().inset(compact ? 24 : 31)
        }
        subtitleLabel.snp.remakeConstraints { make in
            make.top.equalTo(discountView.snp.bottom).offset(compact ? 4 : 5)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        timerPill.snp.remakeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(compact ? 8 : 26)
            make.centerX.equalToSuperview()
            make.height.equalTo(50)
        }
        planCard.snp.remakeConstraints { make in
            make.top.equalTo(timerPill.snp.bottom).offset(compact ? 8 : 24)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(compact ? 150 : 164)
        }
        includedLabel.snp.remakeConstraints { make in
            make.top.equalTo(planCard.snp.bottom).offset(compact ? 8 : 18)
            make.centerX.equalToSuperview()
            make.bottom.lessThanOrEqualTo(renewalLabel.snp.top).offset(-10)
        }
        purchaseButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 10 : 16)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }
        renewalLabel.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(purchaseButton.snp.top).offset(compact ? -8 : -16)
        }
    }

    private func loadOffer(showFailureAlert: Bool) {
        guard !isProcessing else { return }
        let hadRenderableOffer = offerLoaded

        if !hadRenderableOffer {
            offerLoaded = false
            purchaseButton.isEnabled = false
            purchaseButton.setTitle("Loading offer…", for: .normal)
            oldPriceLabel.attributedText = struckPrice("Loading…")
            oldPriceLabel.isHidden = false
            priceLabel.attributedText = priceText(price: "Loading…", period: "")
            weeklyLabel.text = "Loading current App Store price"
            discountView.setLoading()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let offer = try await self.purchaseManager.loadSpecialOffer()
                self.applyOffer(offer, animated: self.viewIfLoaded?.window != nil)
                self.logPresentationIfNeeded()
            } catch {
                if hadRenderableOffer || self.offerLoaded {
                    print("[Adapty] Keeping cached special offer after refresh failure: \(error.localizedDescription)")
                    return
                }

                self.discountView.setOffer(percent: nil, fallbackText: "Offer")
                self.oldPriceLabel.attributedText = self.struckPrice("Unavailable")
                self.priceLabel.attributedText = self.priceText(price: "Unavailable", period: "")
                self.weeklyLabel.text = "Please try again"
                self.purchaseButton.setTitle("Retry offer", for: .normal)
                self.purchaseButton.isEnabled = true
                self.setOfferContentHidden(false, animated: true)
                if showFailureAlert {
                    self.showAlert(
                        title: "Offer unavailable",
                        message: "We couldn’t load the current special offer from the App Store. Check your connection and try again.\n\n\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @discardableResult
    private func applyCachedOffer(animated: Bool) -> Bool {
        guard let offer = purchaseManager.cachedSpecialOffer() else { return false }
        applyOffer(offer, animated: animated)
        return true
    }

    private func applyOffer(_ offer: SpecialOfferInfo, animated: Bool) {
        let title = offer.product.localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        annualLabel.text = title.isEmpty ? "Annual Access" : title

        if let regular = offer.regularAnnualPrice,
           regular != offer.product.localizedPrice {
            oldPriceLabel.attributedText = struckPrice(regular)
            oldPriceLabel.isHidden = false
        } else {
            oldPriceLabel.attributedText = struckPrice(" ")
            oldPriceLabel.isHidden = true
        }

        priceLabel.attributedText = priceText(
            price: offer.product.localizedPrice,
            period: "/ year"
        )
        if let weekly = offer.product.weeklyEquivalentPrice {
            weeklyLabel.text = "Only \(weekly) per week"
        } else {
            weeklyLabel.text = offer.product.localizedSubscriptionPeriod ?? "Annual subscription"
        }
        discountView.setOffer(percent: offer.discountPercent, fallbackText: offer.product.localizedPrice)
        offerLoaded = true
        purchaseButton.setTitle("Claim this offer", for: .normal)
        purchaseButton.isEnabled = !isProcessing
        setOfferContentHidden(false, animated: animated)
    }

    private func setOfferContentHidden(_ hidden: Bool, animated: Bool) {
        let views: [UIView] = [discountView, planCard, renewalLabel, purchaseButton]
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
        _ = applyCachedOffer(animated: viewIfLoaded?.window != nil)
        logPresentationIfNeeded()
    }

    private func logPresentationIfNeeded() {
        guard offerLoaded, viewIfLoaded?.window != nil, !hasLoggedPresentation else { return }
        hasLoggedPresentation = true
        Task { [purchaseManager] in
            await purchaseManager.logPresentation(for: .specialOffer)
        }
    }

    private func struckPrice(_ value: String) -> NSAttributedString {
        NSAttributedString(
            string: value,
            attributes: [
                .font: UIFont.appSemiBoldFont(size: 18),
                .foregroundColor: DesignSystem.Color.textSecondary,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
    }

    private func priceText(price: String, period: String) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: price,
            attributes: [.font: UIFont.appHeavyFont(size: 42), .foregroundColor: UIColor.black]
        )
        if !period.isEmpty {
            text.append(NSAttributedString(
                string: " \(period)",
                attributes: [.font: UIFont.appSemiBoldFont(size: 18), .foregroundColor: UIColor.black]
            ))
        }
        return text
    }

    private func setProcessing(_ processing: Bool, title: String) {
        isProcessing = processing
        restoreButton.isEnabled = !processing
        closeButton.isEnabled = !processing
        purchaseButton.isEnabled = !processing
        restoreButton.alpha = processing ? 0.55 : 1
        purchaseButton.setTitle(title, for: .normal)
    }

    private func updateTimer() {
        let remaining = LimitedOfferManager.shared.remaining()
        guard remaining > 0 else {
            timer?.invalidate()
            timer = nil
            // If Apple already has a checkout/restore in flight, let that operation finish instead
            // of dismissing its presenting controller underneath the system purchase sheet.
            guard !isProcessing else { return }
            dismiss(animated: true) { [weak self] in self?.onFinished?() }
            return
        }
        let value = Int(ceil(remaining))
        timerLabel.text = String(format: "%02d:%02d", value / 60, value % 60)
    }

    @objc private func restoreTapped() {
        guard !isProcessing else { return }
        setProcessing(true, title: "Restoring…")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.purchaseManager.restorePurchases()
            self.setProcessing(false, title: self.offerLoaded ? "Claim this offer" : "Retry offer")

            switch result {
            case .restored:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.dismiss(animated: true) { [weak self] in self?.onFinished?() }
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

    @objc private func closeTapped() {
        guard !isProcessing else { return }
        dismiss(animated: true) { [weak self] in self?.onFinished?() }
    }

    @objc private func purchaseTapped() {
        guard !isProcessing else { return }
        guard offerLoaded else {
            loadOffer(showFailureAlert: true)
            return
        }

        setProcessing(true, title: "Processing…")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.purchaseManager.purchase(.annual, placement: .specialOffer)
            self.setProcessing(false, title: "Claim this offer")

            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.dismiss(animated: true) { [weak self] in self?.onFinished?() }
            case .cancelled:
                if LimitedOfferManager.shared.remaining() <= 0 {
                    self.dismiss(animated: true) { [weak self] in self?.onFinished?() }
                }
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

private final class DiscountShimmerView: UIView {
    private let percentLabel = UILabel()
    private let offLabel = UILabel()
    private let shimmerOverlay = UIView()
    private let shimmerMaskLabel = UILabel()
    private let shimmerStrip = UIView()
    private let shimmerGradient = CAGradientLayer()
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        percentLabel.font = .appHeavyFont(size: 82)
        percentLabel.textColor = DesignSystem.Color.brandGreen

        offLabel.text = " off"
        offLabel.font = .appBoldFont(size: 82)
        offLabel.textColor = .black

        shimmerOverlay.isUserInteractionEnabled = false
        shimmerOverlay.clipsToBounds = true
        shimmerMaskLabel.font = .appHeavyFont(size: 82)
        shimmerMaskLabel.textColor = .white
        shimmerMaskLabel.backgroundColor = .clear
        shimmerOverlay.mask = shimmerMaskLabel

        shimmerStrip.isUserInteractionEnabled = false
        shimmerStrip.alpha = 0
        shimmerStrip.transform = CGAffineTransform(rotationAngle: -0.18)
        shimmerGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.90).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerGradient.locations = [0, 0.5, 1]
        shimmerGradient.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerGradient.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerStrip.layer.addSublayer(shimmerGradient)
        shimmerOverlay.addSubview(shimmerStrip)

        addSubview(percentLabel)
        addSubview(offLabel)
        addSubview(shimmerOverlay)

        percentLabel.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        offLabel.snp.makeConstraints { make in
            make.leading.equalTo(percentLabel.snp.trailing)
            make.trailing.top.bottom.equalToSuperview()
        }
        setLoading()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerOverlay.frame = percentLabel.frame
        shimmerMaskLabel.frame = shimmerOverlay.bounds
        shimmerGradient.frame = shimmerStrip.bounds
    }

    func setLoading() {
        percentLabel.font = .appHeavyFont(size: 82)
        shimmerMaskLabel.font = .appHeavyFont(size: 82)
        percentLabel.text = "…"
        shimmerMaskLabel.text = "…"
        offLabel.isHidden = true
        setNeedsLayout()
    }

    func setOffer(percent: Int?, fallbackText: String) {
        if let percent {
            let text = "\(percent)%"
            percentLabel.font = .appHeavyFont(size: 82)
            shimmerMaskLabel.font = .appHeavyFont(size: 82)
            percentLabel.text = text
            shimmerMaskLabel.text = text
            offLabel.isHidden = false
        } else {
            percentLabel.font = .appHeavyFont(size: 54)
            shimmerMaskLabel.font = .appHeavyFont(size: 54)
            percentLabel.text = fallbackText
            shimmerMaskLabel.text = fallbackText
            offLabel.isHidden = true
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    func startShimmering() {
        stopShimmering()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.performShimmer()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.performShimmer()
        }
    }

    func stopShimmering() {
        timer?.invalidate()
        timer = nil
        shimmerStrip.layer.removeAllAnimations()
        shimmerStrip.alpha = 0
    }

    private func performShimmer() {
        guard window != nil else { return }
        layoutIfNeeded()
        let textWidth = max(shimmerOverlay.bounds.width, 1)
        let stripWidth: CGFloat = 54
        shimmerStrip.frame = CGRect(
            x: -stripWidth - 12,
            y: -8,
            width: stripWidth,
            height: shimmerOverlay.bounds.height + 16
        )
        shimmerGradient.frame = shimmerStrip.bounds
        shimmerStrip.alpha = 1

        UIView.animate(
            withDuration: 0.95,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.shimmerStrip.frame.origin.x = textWidth + 12
        } completion: { _ in
            self.shimmerStrip.alpha = 0
        }
    }
}
