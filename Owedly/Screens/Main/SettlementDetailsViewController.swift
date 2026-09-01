import UIKit
import SnapKit
import SafariServices

final class SettlementDetailsViewController: UIViewController {
    private let settlement: Settlement
    private let accentColor: UIColor
    private let purchaseManager = PurchaseManager.shared

    private let scrollView = EdgeFadingScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let actionBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let trackedDimView = UIView()
    private let actionButton = UIButton(type: .system)
    private let filedPanel = UIView()
    private let filedDateLabel = UILabel()
    private let filedDivider = UIView()
    private let filedButtons = UIStackView()
    private let stopTrackingButton = UIButton(type: .system)
    private let goToWebsiteButton = UIButton(type: .system)
    private var actionBarHeightConstraint: Constraint?

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let payoutLabel = UILabel()
    private let tagsStack = UIStackView()
    private let dateCaptionLabel = UILabel()
    private let dateValueLabel = UILabel()

    private var awaitingWebsiteReturn = false
    private weak var presentedSafariController: SFSafariViewController?

    init(settlement: Settlement) {
        self.settlement = settlement
        self.accentColor = settlement.status == .upcoming ? DesignSystem.Color.iconBlue : DesignSystem.Color.brandGreen
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureNavigationBarAppearance()
        configureLayout()
        configureContent()
        refreshActionButton()
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The bar is already visible in both tabs. Do not animate a redundant hide/show update
        // while the detail controller is entering; on iOS 26 that could animate its first layout.
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .light
        configureNavigationBarAppearance()
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        actionBar.layer.cornerRadius = 16
        actionBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        actionBar.clipsToBounds = true

        let baseHeight: CGFloat = isFiledRecord ? 158 : 96
        let desiredHeight = baseHeight + view.safeAreaInsets.bottom
        actionBarHeightConstraint?.update(offset: desiredHeight)

        let covered = max(116, desiredHeight + 16)
        if abs(scrollView.contentInset.bottom - covered) > 0.5 {
            scrollView.contentInset.bottom = covered
            scrollView.verticalScrollIndicatorInsets.bottom = covered
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureNavigation() {
        navigationItem.title = "Settlement Details"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = nil
        navigationController?.navigationBar.tintColor = .black
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.black]
    }

    /// On iOS 26 the system Liquid Glass navigation bar owns the scroll-edge treatment.
    /// On older systems the detail viewport starts below the bar, so content can never
    /// collide with the back button/title. The bar itself stays visually lightweight and
    /// is separated from the content only by a subtle hairline.
    private func configureNavigationBarAppearance() {
        guard let bar = navigationController?.navigationBar else { return }
        navigationController?.view.overrideUserInterfaceStyle = .light
        bar.overrideUserInterfaceStyle = .light
        bar.prefersLargeTitles = false
        bar.barStyle = .default
        bar.tintColor = .black

        if #available(iOS 26.0, *) { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.14)
        appearance.titleTextAttributes = [
            .font: UIFont.appSemiBoldFont(size: 16),
            .foregroundColor: UIColor.black
        ]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.fadeLength = 32
        scrollView.topFadeThreshold = 8
        scrollView.fadesBottomEdge = false

        if #available(iOS 26.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .always
            scrollView.fadesTopEdge = false
        } else {
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.fadesTopEdge = true
        }

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0

        actionBar.layer.borderWidth = 0.5
        actionBar.layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor

        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = .appSemiBoldFont(size: 20)
        actionButton.layer.cornerRadius = DesignSystem.Radius.button
        actionButton.clipsToBounds = true
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        filedDateLabel.font = .appSemiBoldFont(size: 24)
        filedDateLabel.textColor = .black
        filedDateLabel.numberOfLines = 1
        filedDateLabel.adjustsFontSizeToFitWidth = true
        filedDateLabel.minimumScaleFactor = 0.72
        filedDivider.backgroundColor = UIColor.black.withAlphaComponent(0.10)

        filedButtons.axis = .horizontal
        filedButtons.alignment = .fill
        filedButtons.distribution = .fillEqually
        filedButtons.spacing = 12

        stopTrackingButton.backgroundColor = UIColor(hex: 0xCC0C0C)
        stopTrackingButton.setTitle("Stop Tracking", for: .normal)
        stopTrackingButton.setTitleColor(.white, for: .normal)
        stopTrackingButton.titleLabel?.font = .appSemiBoldFont(size: 20)
        stopTrackingButton.layer.cornerRadius = DesignSystem.Radius.button
        stopTrackingButton.clipsToBounds = true
        stopTrackingButton.addTarget(self, action: #selector(stopTrackingTapped), for: .touchUpInside)

        goToWebsiteButton.backgroundColor = DesignSystem.Color.brandGreen
        goToWebsiteButton.setTitle("Go to Website", for: .normal)
        goToWebsiteButton.setTitleColor(.white, for: .normal)
        goToWebsiteButton.titleLabel?.font = .appSemiBoldFont(size: 20)
        goToWebsiteButton.layer.cornerRadius = DesignSystem.Radius.button
        goToWebsiteButton.clipsToBounds = true
        goToWebsiteButton.addTarget(self, action: #selector(trackedWebsiteTapped), for: .touchUpInside)

        trackedDimView.backgroundColor = UIColor.black.withAlphaComponent(0.10)
        trackedDimView.isUserInteractionEnabled = false
        trackedDimView.isHidden = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)
        view.addSubview(trackedDimView)
        view.addSubview(actionBar)
        actionBar.contentView.addSubview(actionButton)
        actionBar.contentView.addSubview(filedPanel)
        filedPanel.addSubview(filedDateLabel)
        filedPanel.addSubview(filedDivider)
        filedPanel.addSubview(filedButtons)
        filedButtons.addArrangedSubview(stopTrackingButton)
        filedButtons.addArrangedSubview(goToWebsiteButton)

        scrollView.snp.makeConstraints { make in
            if #available(iOS 26.0, *) {
                make.edges.equalToSuperview()
            } else {
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
                make.leading.trailing.bottom.equalToSuperview()
            }
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().offset(-24)
        }
        trackedDimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        actionBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            actionBarHeightConstraint = make.height.equalTo(130).constraint
        }
        actionButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(56)
        }
        filedPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(118)
        }
        filedDateLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        filedDivider.snp.makeConstraints { make in
            make.top.equalTo(filedDateLabel.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(1)
        }
        filedButtons.snp.makeConstraints { make in
            make.top.equalTo(filedDivider.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(56)
        }
    }

    private func configureContent() {
        contentStack.addArrangedSubview(makeOverviewView())
        contentStack.setCustomSpacing(12, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeDateCardContainer())
        contentStack.setCustomSpacing(16, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeMainInformationView())
    }

    private func makeOverviewView() -> UIView {
        let container = UIView()
        container.addSubview(iconContainer)
        container.addSubview(titleLabel)
        container.addSubview(payoutLabel)
        container.addSubview(tagsStack)

        iconContainer.backgroundColor = .white
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.borderWidth = 1
        iconContainer.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        iconContainer.clipsToBounds = true

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconContainer.addSubview(iconView)
        iconView.snp.makeConstraints { $0.edges.equalToSuperview() }
        SettlementImageLoader.shared.load(
            settlement.imageURL,
            into: iconView,
            placeholder: UIImage(systemName: "checkmark.shield"),
            placeholderTint: accentColor
        )

        titleLabel.text = settlement.title
        titleLabel.font = .appBoldFont(size: 24)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.numberOfLines = 0

        payoutLabel.text = displayPayoutText
        payoutLabel.font = .appHeavyFont(size: 32)
        payoutLabel.textColor = accentColor
        payoutLabel.numberOfLines = 1
        payoutLabel.adjustsFontSizeToFitWidth = true
        payoutLabel.minimumScaleFactor = 0.72

        tagsStack.axis = .horizontal
        tagsStack.alignment = .center
        tagsStack.spacing = 8
        tagsStack.addArrangedSubview(SettlementDetailTagView(title: settlement.category.isEmpty ? "Other" : settlement.category, color: accentColor))
        tagsStack.addArrangedSubview(SettlementDetailTagView(title: settlement.status == .upcoming ? "Upcoming" : "Open", color: accentColor))

        iconContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalToSuperview()
            make.size.equalTo(58)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconContainer.snp.trailing).offset(16)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalToSuperview()
        }
        payoutLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
        tagsStack.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(payoutLabel.snp.bottom).offset(12)
            make.bottom.equalToSuperview()
        }
        return container
    }

    private func makeDateCardContainer() -> UIView {
        let outer = UIView()
        let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        surface.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        surface.layer.cornerRadius = 16
        surface.layer.borderWidth = 1
        surface.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        surface.clipsToBounds = true

        let iconBox = UIView()
        iconBox.backgroundColor = accentColor.withAlphaComponent(0.06)
        iconBox.layer.cornerRadius = 12
        iconBox.layer.borderWidth = 1
        iconBox.layer.borderColor = DesignSystem.Color.cardBorder.cgColor

        let calendar = UIImageView(image: UIImage(systemName: "calendar"))
        calendar.tintColor = accentColor
        calendar.contentMode = .scaleAspectFit
        calendar.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .light)

        dateCaptionLabel.font = .appMediumFont(size: 12)
        dateCaptionLabel.textColor = UIColor.black.withAlphaComponent(0.60)
        dateCaptionLabel.text = dateCardCaption

        dateValueLabel.font = .appSemiBoldFont(size: 24)
        dateValueLabel.textColor = accentColor
        dateValueLabel.text = dateCardValue
        dateValueLabel.adjustsFontSizeToFitWidth = true
        dateValueLabel.minimumScaleFactor = 0.75

        outer.addSubview(surface)
        surface.contentView.addSubview(iconBox)
        iconBox.addSubview(calendar)
        surface.contentView.addSubview(dateCaptionLabel)
        surface.contentView.addSubview(dateValueLabel)

        outer.snp.makeConstraints { $0.height.equalTo(102) }
        surface.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.bottom.equalToSuperview().inset(12)
        }
        iconBox.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }
        calendar.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(28)
        }
        dateCaptionLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBox.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        dateValueLabel.snp.makeConstraints { make in
            make.leading.equalTo(dateCaptionLabel)
            make.top.equalTo(dateCaptionLabel.snp.bottom).offset(1)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        return outer
    }

    private func makeMainInformationView() -> UIView {
        let wrapper = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24

        stack.addArrangedSubview(makeTextSection(title: "What this case is about", paragraphs: [caseDescription]))
        stack.addArrangedSubview(makeRequirementsSection())
        stack.addArrangedSubview(makeTextSection(title: "Details", paragraphs: detailParagraphs))
        stack.addArrangedSubview(makeTextSection(title: "Legal Notice", paragraphs: legalNoticeParagraphs))

        wrapper.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
        return wrapper
    }

    private func makeTextSection(title: String, paragraphs: [String]) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.alignment = .fill
        section.spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .appSemiBoldFont(size: 18)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        section.addArrangedSubview(titleLabel)

        let cleanParagraphs = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for paragraph in cleanParagraphs {
            let label = UILabel()
            label.text = paragraph
            label.font = .appMediumFont(size: 16)
            label.textColor = UIColor.black.withAlphaComponent(0.70)
            label.numberOfLines = 0
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            section.addArrangedSubview(label)
        }
        return section
    }

    private func makeRequirementsSection() -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.alignment = .fill
        section.spacing = 8

        let title = UILabel()
        title.text = "Requirements"
        title.font = .appSemiBoldFont(size: 18)
        title.textColor = DesignSystem.Color.textPrimary

        let card = UIStackView()
        card.axis = .vertical
        card.alignment = .fill
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        card.clipsToBounds = true

        for requirement in requirementTexts {
            card.addArrangedSubview(SettlementRequirementRow(text: requirement, color: accentColor))
        }

        section.addArrangedSubview(title)
        section.addArrangedSubview(card)
        return section
    }

    private var displayPayoutText: String {
        let raw = settlement.payoutText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        return settlement.status == .upcoming ? "Payout TBD" : "Payout varies"
    }

    private var dateCardCaption: String {
        if isFiledRecord { return "Claimed" }
        if settlement.status == .upcoming {
            return settlement.createdAt == nil ? "Status" : "Announced"
        }
        return "Claim deadline"
    }

    private var dateCardValue: String {
        if let filedAt = ClaimTrackingStore.shared.record(for: settlement.id)?.filedAt,
           ClaimTrackingStore.shared.record(for: settlement.id)?.state == .filed {
            return Self.dateFormatter.string(from: filedAt)
        }
        if settlement.status == .upcoming {
            if let announced = settlement.createdAt { return Self.dateFormatter.string(from: announced) }
            return "Coming soon"
        }
        if let deadline = settlement.deadline { return Self.dateFormatter.string(from: deadline) }
        return "Not listed"
    }

    private var caseDescription: String {
        let text = settlement.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return "Review the official settlement notice for a complete description of the case and who may be included."
    }

    private var requirementTexts: [String] {
        var result: [String] = []

        if let period = settlement.classPeriodText?.trimmingCharacters(in: .whitespacesAndNewlines), !period.isEmpty {
            result.append("Class period: \(period)")
        } else if settlement.status == .upcoming {
            result.append("The eligible class period will be confirmed when claims open")
        } else {
            result.append("Review the official notice for the eligible class period")
        }

        if settlement.isNationwide {
            result.append("Available to eligible residents in the United States")
        } else if !settlement.eligibleStates.isEmpty {
            result.append("Location eligibility: \(settlement.eligibleStates.joined(separator: ", "))")
        } else {
            result.append("Residency requirements are listed in the official settlement notice")
        }

        switch settlement.proofRequired {
        case .some(true):
            result.append("Proof or supporting documentation may be required")
        case .some(false):
            result.append("No proof requirement is listed in the current settlement summary")
        case .none:
            result.append("Proof requirements are listed in the official settlement notice")
        }
        return result
    }

    private var detailParagraphs: [String] {
        let eligibility = settlement.eligibilityDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var paragraphs: [String] = []
        if !eligibility.isEmpty && eligibility.caseInsensitiveCompare(caseDescription) != .orderedSame {
            paragraphs.append(eligibility)
        }

        var summaryParts: [String] = []
        if let payout = settlement.payoutText, !payout.isEmpty { summaryParts.append("Potential payout: \(payout).") }
        if let period = settlement.classPeriodText, !period.isEmpty { summaryParts.append("Class period: \(period).") }
        if let proof = settlement.proofRequired {
            summaryParts.append(proof ? "Supporting proof may be required." : "The current listing does not indicate that proof is required.")
        }
        if !summaryParts.isEmpty { paragraphs.append(summaryParts.joined(separator: " ")) }

        if paragraphs.isEmpty {
            paragraphs.append("Additional eligibility and filing details are available in the official settlement notice and on the settlement administrator’s website.")
        }
        return paragraphs
    }

    private var legalNoticeParagraphs: [String] {
        [
            "Owedly summarizes public settlement information for convenience and does not determine whether you are eligible.",
            "Court-approved settlement documents and the official settlement administrator control eligibility, deadlines, required documents, and payment amounts.",
            "Review the official notice before submitting a claim."
        ]
    }

    @objc private func actionTapped() {
        if settlement.status == .upcoming {
            handleNotifyTapped()
            return
        }

        if isFiledRecord {
            trackedWebsiteTapped()
            return
        }

        presentLegalNotice()
    }

    private func handleNotifyTapped() {
        if UpcomingSettlementWatchStore.shared.isWatching(settlement.id) {
            UpcomingSettlementWatchStore.shared.unwatch(settlement.id)
            refreshActionButton()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let granted = await NotificationManager.shared.requestAuthorizationAndActivate()
            await MainActor.run {
                guard granted else {
                    let alert = UIAlertController(
                        title: "Notifications are off",
                        message: "Enable notifications in Settings if you want Owedly to alert you about settlement updates.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    return
                }
                UpcomingSettlementWatchStore.shared.watch(self.settlement)
                self.refreshActionButton()
            }
        }
    }

    private var isFiledRecord: Bool {
        ClaimTrackingStore.shared.record(for: settlement.id)?.state == .filed
    }

    private func refreshActionButton() {
        dateCaptionLabel.text = dateCardCaption
        dateValueLabel.text = dateCardValue

        if settlement.status == .upcoming {
            trackedDimView.isHidden = true
            filedPanel.isHidden = true
            actionButton.isHidden = false
            let watching = UpcomingSettlementWatchStore.shared.isWatching(settlement.id)
            actionButton.backgroundColor = DesignSystem.Color.iconBlue
            actionButton.setTitle(watching ? "Notifications On" : "Notify", for: .normal)
            view.setNeedsLayout()
            return
        }

        if let tracked = ClaimTrackingStore.shared.record(for: settlement.id), tracked.state == .filed {
            trackedDimView.isHidden = false
            actionButton.isHidden = true
            filedPanel.isHidden = false
            let date = tracked.filedAt ?? tracked.startedAt
            let prefix = NSAttributedString(
                string: "You claimed on ",
                attributes: [.foregroundColor: UIColor.black, .font: UIFont.appSemiBoldFont(size: 24)]
            )
            let suffix = NSAttributedString(
                string: Self.dateFormatter.string(from: date),
                attributes: [.foregroundColor: DesignSystem.Color.brandGreen, .font: UIFont.appSemiBoldFont(size: 24)]
            )
            let combined = NSMutableAttributedString(attributedString: prefix)
            combined.append(suffix)
            filedDateLabel.attributedText = combined
            view.setNeedsLayout()
            return
        }

        trackedDimView.isHidden = true
        filedPanel.isHidden = true
        actionButton.isHidden = false
        actionButton.backgroundColor = DesignSystem.Color.brandGreen
        switch ClaimTrackingStore.shared.record(for: settlement.id)?.state {
        case .needsAction:
            actionButton.setTitle("Continue Claim", for: .normal)
        default:
            actionButton.setTitle("Claim", for: .normal)
        }
        view.setNeedsLayout()
    }

    @objc private func stopTrackingTapped() {
        ClaimTrackingStore.shared.stopTracking(settlementID: settlement.id)
        refreshActionButton()
        navigationController?.popViewController(animated: true)
    }

    @objc private func trackedWebsiteTapped() {
        ensurePremiumAccess { [weak self] in
            guard let self,
                  let url = self.settlement.officialClaimURL ?? self.settlement.sourceURL else { return }
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = DesignSystem.Color.brandGreen
            self.present(safari, animated: true)
        }
    }

    private func presentLegalNotice() {
        weak var sheetReference: SettlementActionSheetController?
        let sheet = SettlementActionSheetController(
            title: "Legal Notice",
            paragraphs: [
                "Owedly provides settlement information for convenience and does not provide legal advice.",
                "Eligibility, deadlines, jurisdiction, claim requirements, and payment amounts are determined by the court-approved settlement documents and the official settlement administrator.",
                "By continuing, you’ll leave Owedly to complete the claim on the official website. Review the official notice before submitting."
            ],
            actions: [
                .init(title: "Continue", style: .primary, handler: { [weak self] in
                    guard let self, let sheetReference else { return }
                    sheetReference.transition(
                        title: "External Application Required",
                        paragraphs: [
                            "You must submit your claim through the settlement’s official website. Don’t worry, we’re working hard on getting all settlements applicable within the app."
                        ],
                        actions: [
                            .init(title: "Go to Website", style: .primary, handler: { [weak self] in
                                self?.openOfficialClaimWebsite()
                            }),
                            .init(title: "Cancel", style: .secondary, handler: nil)
                        ]
                    )
                }, dismissesSheet: false)
            ]
        )
        sheetReference = sheet
        present(sheet, animated: false)
    }

    private func openOfficialClaimWebsite() {
        ensurePremiumAccess { [weak self] in
            guard let self else { return }
            guard let url = self.settlement.officialClaimURL else {
                let alert = UIAlertController(
                    title: "Official website unavailable",
                    message: "This listing does not currently include an official claim-form URL. Try refreshing the settlement catalog or review the source listing later.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                return
            }

            ClaimTrackingStore.shared.markNeedsAction(self.settlement)
            self.refreshActionButton()
            self.awaitingWebsiteReturn = true

            let safari = SFSafariViewController(url: url)
            safari.delegate = self
            safari.preferredControlTintColor = DesignSystem.Color.brandGreen
            safari.modalPresentationStyle = .pageSheet
            self.presentedSafariController = safari
            self.present(safari, animated: true) { [weak self, weak safari] in
                safari?.presentationController?.delegate = self
            }
        }
    }

    private func ensurePremiumAccess(continueAction: @escaping () -> Void) {
        guard purchaseManager.isPurchased else {
            presentDefaultPaywall(onEntitlementUnlocked: continueAction)
            return
        }
        continueAction()
    }

    private func presentDefaultPaywall(onEntitlementUnlocked: @escaping () -> Void) {
        let result = SettlementScanner.shared.latestResult
            ?? SettlementScanner.shared.scan([settlement], profile: OnboardingStore.shared.draft)

        let paywall = PaywallViewController(scanResult: result)
        paywall.onClose = { [weak paywall] in
            paywall?.dismiss(animated: true)
        }
        paywall.onPurchaseSuccess = { [weak self, weak paywall] in
            paywall?.dismiss(animated: true) {
                onEntitlementUnlocked()
                self?.refreshActionButton()
            }
        }
        paywall.onRestoreSuccess = { [weak self, weak paywall] in
            paywall?.dismiss(animated: true) {
                onEntitlementUnlocked()
                self?.refreshActionButton()
            }
        }
        present(paywall, animated: true)
    }

    private func presentFiledQuestion() {
        presentedSafariController = nil

        let sheet = SettlementActionSheetController(
            title: "Did you file this claim?",
            paragraphs: [
                "Select yes if you submitted the form on the external website and we’ll mark this settlement as claimed."
            ],
            actions: [
                .init(title: "No", style: .secondary, handler: { [weak self] in
                    guard let self else { return }
                    ClaimTrackingStore.shared.markNeedsAction(self.settlement)
                    self.refreshActionButton()
                }),
                .init(title: "Yes", style: .primary, handler: { [weak self] in
                    guard let self else { return }
                    ClaimTrackingStore.shared.markFiled(self.settlement)
                    self.refreshActionButton()
                })
            ],
            buttonAxis: .horizontal
        )
        present(sheet, animated: false)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

extension SettlementDetailsViewController: SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        guard awaitingWebsiteReturn else { return }
        awaitingWebsiteReturn = false
        controller.dismiss(animated: true) { [weak self] in
            self?.presentFiledQuestion()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === presentedSafariController, awaitingWebsiteReturn else { return }
        awaitingWebsiteReturn = false
        presentFiledQuestion()
    }
}

private final class SettlementDetailTagView: UIView {
    init(title: String, color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = color.withAlphaComponent(0.04)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor

        let label = UILabel()
        label.text = title
        label.font = .appMediumFont(size: 12)
        label.textColor = color
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(8)
            make.top.bottom.equalToSuperview().inset(4)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SettlementRequirementRow: UIView {
    init(text: String, color: UIColor) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        let label = UILabel()
        label.text = text
        label.font = .appMediumFont(size: 14)
        label.textColor = UIColor.black.withAlphaComponent(0.70)
        label.numberOfLines = 0

        addSubview(icon)
        addSubview(label)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(19)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(8)
            make.trailing.top.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension SettlementDetailsViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        self.scrollView.updateFadeMask()
    }
}


// MARK: - Figma-style action sheets

final class SettlementActionSheetController: UIViewController {
    enum ButtonStyle {
        case primary
        case secondary
    }

    struct Action {
        let title: String
        let style: ButtonStyle
        let handler: (() -> Void)?
        let dismissesSheet: Bool

        init(
            title: String,
            style: ButtonStyle,
            handler: (() -> Void)?,
            dismissesSheet: Bool = true
        ) {
            self.title = title
            self.style = style
            self.handler = handler
            self.dismissesSheet = dismissesSheet
        }
    }

    private let sheetView = UIView()
    private let dimView = UIView()
    private let contentStack = UIStackView()
    private var actions: [Action]
    private var buttonAxis: NSLayoutConstraint.Axis
    private var hasPresentedInitialAnimation = false
    private var isTransitioningContent = false

    init(
        title: String,
        paragraphs: [String],
        actions: [Action],
        buttonAxis: NSLayoutConstraint.Axis = .vertical
    ) {
        self.actions = actions
        self.buttonAxis = buttonAxis
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve

        buildContent(title: title, paragraphs: paragraphs)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        dimView.alpha = 0

        sheetView.backgroundColor = .white
        sheetView.layer.cornerRadius = 16
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.clipsToBounds = true

        view.addSubview(dimView)
        view.addSubview(sheetView)
        sheetView.addSubview(contentStack)

        dimView.snp.makeConstraints { $0.edges.equalToSuperview() }
        sheetView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.greaterThanOrEqualTo(view.safeAreaLayoutGuide.snp.top).offset(20)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(32)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-16)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !hasPresentedInitialAnimation else { return }
        view.layoutIfNeeded()
        dimView.alpha = 0
        sheetView.transform = offscreenTransform()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresentedInitialAnimation else { return }
        hasPresentedInitialAnimation = true
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.94,
            initialSpringVelocity: 0.12,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 1
            self.sheetView.transform = .identity
        }
    }

    private func buildContent(title: String, paragraphs: [String]) {
        contentStack.arrangedSubviews.forEach { arrangedSubview in
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .appSemiBoldFont(size: 24)
        titleLabel.textColor = .black
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        for paragraph in paragraphs {
            let label = UILabel()
            label.text = paragraph
            label.font = .appMediumFont(size: 16)
            label.textColor = UIColor.black.withAlphaComponent(0.70)
            label.numberOfLines = 0
            contentStack.addArrangedSubview(label)
        }

        let buttonStack = UIStackView()
        buttonStack.axis = buttonAxis
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 10

        for (index, action) in actions.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(action.title, for: .normal)
            button.titleLabel?.font = .appSemiBoldFont(size: 20)
            button.layer.cornerRadius = 12
            button.clipsToBounds = true
            button.snp.makeConstraints { $0.height.equalTo(56) }
            switch action.style {
            case .primary:
                button.backgroundColor = DesignSystem.Color.brandGreen
                button.setTitleColor(.white, for: .normal)
            case .secondary:
                button.backgroundColor = .clear
                button.setTitleColor(.black, for: .normal)
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor
            }
            button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)
            buttonStack.addArrangedSubview(button)
        }

        contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(buttonStack)
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        guard !isTransitioningContent, actions.indices.contains(sender.tag) else { return }
        let action = actions[sender.tag]
        if action.dismissesSheet {
            dismissAnimated { action.handler?() }
        } else {
            action.handler?()
        }
    }

    func transition(
        title: String,
        paragraphs: [String],
        actions: [Action],
        buttonAxis: NSLayoutConstraint.Axis = .vertical
    ) {
        guard !isTransitioningContent else { return }
        isTransitioningContent = true
        view.isUserInteractionEnabled = false

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.sheetView.transform = self.offscreenTransform()
        } completion: { _ in
            self.actions = actions
            self.buttonAxis = buttonAxis
            self.buildContent(title: title, paragraphs: paragraphs)
            UIView.performWithoutAnimation {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.sheetView.transform = self.offscreenTransform()
            }

            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.96,
                initialSpringVelocity: 0.08,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.sheetView.transform = .identity
            } completion: { _ in
                self.isTransitioningContent = false
                self.view.isUserInteractionEnabled = true
            }
        }
    }

    private func offscreenTransform() -> CGAffineTransform {
        CGAffineTransform(translationX: 0, y: max(sheetView.bounds.height, 1) + 30)
    }

    private func dismissAnimated(completion: @escaping () -> Void) {
        guard !isTransitioningContent else { return }
        isTransitioningContent = true
        view.isUserInteractionEnabled = false
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 0
            self.sheetView.transform = self.offscreenTransform()
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }
}
