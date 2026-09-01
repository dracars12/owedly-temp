import UIKit
import SnapKit

// MARK: - Placeholder destinations

enum AppLinks {
    static let privacy = URL(string: "https://owedly.online/privacy.html")!
    static let terms = URL(string: "https://owedly.online/terms.html")!
    static let supportEmail = "info@owedly.online"

    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:])
    }

    static func openSupport(from presenter: UIViewController) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Owedly Support")]
        if let url = components.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            let alert = UIAlertController(
                title: "Support",
                message: "Email us at \(supportEmail)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: true)
        }
    }
}

private enum MatchProfileRefresh {
    static func rescanCachedCatalog() {
        Task {
            _ = await SettlementScanner.shared.loadAndScan(refreshPolicy: .cacheOnly)
        }
    }
}

// MARK: - Settings

final class SettingsViewController: UIViewController {
    private let scrollView = EdgeFadingScrollView()
    private let contentStack = UIStackView()
    private var settlementAlertsSwitch: UISwitch?
    private var deadlineRemindersSwitch: UISwitch?
    private var hasAppeared = false

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        hidesBottomBarWhenPushed = true
    }

    convenience init() { self.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureLayout()
        rebuildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(entitlementChanged),
            name: .owedlyPurchaseEntitlementDidChange,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        if hasAppeared { rebuildContentWithoutAnimation() }
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureNavigation() {
        navigationItem.title = "Settings"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.navigationBar.tintColor = .black
    }

    private func configureLayout() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.fadeLength = 28
        scrollView.fadesTopEdge = true
        scrollView.fadesBottomEdge = true
        contentStack.axis = .vertical
        contentStack.spacing = 0

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }
        contentStack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        settlementAlertsSwitch = nil
        deadlineRemindersSwitch = nil

        if !PurchaseManager.shared.isPurchased {
            let premium = PremiumSettingsBanner()
            premium.addTarget(self, action: #selector(viewPlansTapped), for: .touchUpInside)
            contentStack.addArrangedSubview(wrap(premium, top: 12, bottom: 0))
        }

        let stateText: String = {
            let states = OnboardingStore.shared.draft.selectedStates.sorted()
            if states.isEmpty { return "No info" }
            if states.count == 1 { return states[0] }
            return "\(states.count) selected"
        }()

        let stateRow = SettingsRowControl(
            symbol: "location.fill",
            symbolColor: DesignSystem.Color.brandGreen,
            title: "State",
            detail: stateText,
            showsChevron: true
        )
        stateRow.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)
        let profileRow = SettingsRowControl(
            symbol: "slider.horizontal.3",
            symbolColor: DesignSystem.Color.brandGreen,
            title: "Matching Preferences",
            showsChevron: true
        )
        profileRow.addTarget(self, action: #selector(matchProfileTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(makeSection(title: "MATCHING", rows: [stateRow, profileRow]))

        let alertsSwitch = makeSwitch(isOn: NotificationManager.shared.settlementAlertsEnabled)
        alertsSwitch.addTarget(self, action: #selector(settlementAlertsChanged(_:)), for: .valueChanged)
        settlementAlertsSwitch = alertsSwitch
        let alertsRow = SettingsRowControl(
            symbol: "bell",
            symbolColor: DesignSystem.Color.iconBlue,
            title: "Settlement Alerts",
            accessoryView: alertsSwitch
        )

        let deadlineSwitch = makeSwitch(isOn: NotificationManager.shared.deadlineRemindersEnabled)
        deadlineSwitch.addTarget(self, action: #selector(deadlineRemindersChanged(_:)), for: .valueChanged)
        deadlineRemindersSwitch = deadlineSwitch
        let deadlineRow = SettingsRowControl(
            symbol: "calendar",
            symbolColor: DesignSystem.Color.brandGreen,
            title: "Deadline Reminders",
            accessoryView: deadlineSwitch
        )
        contentStack.addArrangedSubview(makeSection(title: "NOTIFICATIONS", rows: [alertsRow, deadlineRow]))

        let support = SettingsRowControl(symbol: "questionmark.circle", symbolColor: UIColor.black.withAlphaComponent(0.48), title: "Support", showsChevron: true)
        support.addTarget(self, action: #selector(supportTapped), for: .touchUpInside)
        let privacy = SettingsRowControl(symbol: "checkmark.shield", symbolColor: UIColor.black.withAlphaComponent(0.48), title: "Privacy Policy", showsChevron: true)
        privacy.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)
        let terms = SettingsRowControl(symbol: "text.document", symbolColor: UIColor.black.withAlphaComponent(0.48), title: "Terms of Use", showsChevron: true)
        terms.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(makeSection(title: "SUPPORT & LEGAL", rows: [support, privacy, terms], bottom: 8))

        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete Personal Information", for: .normal)
        deleteButton.setTitleColor(UIColor(red: 0.80, green: 0.05, blue: 0.05, alpha: 1), for: .normal)
        deleteButton.titleLabel?.font = .appSemiBoldFont(size: 16)
        deleteButton.addTarget(self, action: #selector(deletePersonalInformationTapped), for: .touchUpInside)
        deleteButton.snp.makeConstraints { $0.height.equalTo(56) }
        contentStack.addArrangedSubview(wrap(deleteButton, top: 4, bottom: 28))
    }

    private func wrap(_ view: UIView, top: CGFloat, bottom: CGFloat) -> UIView {
        let wrapper = UIView()
        wrapper.addSubview(view)
        view.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(top)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(bottom)
        }
        return wrapper
    }

    private func makeSection(title: String, rows: [SettingsRowControl], bottom: CGFloat = 0) -> UIView {
        let wrapper = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .appMediumFont(size: 12)
        titleLabel.textColor = UIColor.black.withAlphaComponent(0.50)

        let card = UIView()
        card.backgroundColor = DesignSystem.Color.cardFill
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        card.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                let separator = UIView()
                separator.backgroundColor = UIColor.black.withAlphaComponent(0.10)
                stack.addArrangedSubview(separator)
                separator.snp.makeConstraints { $0.height.equalTo(1) }
            }
        }

        wrapper.addSubview(titleLabel)
        wrapper.addSubview(card)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(18)
        }
        card.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(bottom)
        }
        return wrapper
    }

    private func makeSwitch(isOn: Bool) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = DesignSystem.Color.brandGreen
        return toggle
    }

    private func rebuildContentWithoutAnimation() {
        UIView.performWithoutAnimation {
            rebuildContent()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        scrollView.updateFadeMask()
    }

    @objc private func entitlementChanged() { rebuildContentWithoutAnimation() }

    @objc private func viewPlansTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let result = SettlementScanner.shared.latestResult ?? SettlementScanner.shared.scan([])
        let paywall = PaywallViewController(scanResult: result)
        paywall.onClose = { [weak paywall] in paywall?.dismiss(animated: true) }
        paywall.onPurchaseSuccess = { [weak self, weak paywall] in
            paywall?.dismiss(animated: true) {
                self?.rebuildContent()
            }
        }
        paywall.onRestoreSuccess = { [weak self, weak paywall] in
            paywall?.dismiss(animated: true) {
                self?.rebuildContent()
            }
        }
        present(paywall, animated: true)
    }

    @objc private func stateTapped() {
        let controller = StateSettingsViewController()
        pushPreparedViewController(controller)
    }

    @objc private func matchProfileTapped() {
        pushPreparedViewController(MatchingPreferencesViewController())
    }

    @objc private func settlementAlertsChanged(_ sender: UISwitch) {
        let desired = sender.isOn
        sender.isEnabled = false
        Task { @MainActor [weak self, weak sender] in
            guard let sender else { return }
            let authorized = await NotificationManager.shared.setSettlementAlertsEnabled(desired)
            if desired && !authorized { sender.setOn(false, animated: true) }
            sender.isEnabled = true
            self?.settlementAlertsSwitch = sender
        }
    }

    @objc private func deadlineRemindersChanged(_ sender: UISwitch) {
        let desired = sender.isOn
        sender.isEnabled = false
        Task { @MainActor [weak self, weak sender] in
            guard let sender else { return }
            let authorized = await NotificationManager.shared.setDeadlineRemindersEnabled(desired)
            if desired && !authorized { sender.setOn(false, animated: true) }
            sender.isEnabled = true
            self?.deadlineRemindersSwitch = sender
        }
    }

    @objc private func supportTapped() { AppLinks.openSupport(from: self) }
    @objc private func privacyTapped() { AppLinks.open(AppLinks.privacy) }
    @objc private func termsTapped() { AppLinks.open(AppLinks.terms) }

    @objc private func deletePersonalInformationTapped() {
        let alert = UIAlertController(
            title: "Delete Personal Information?",
            message: "This clears your matching profile, saved claim activity and watched settlements from this device. Your purchase status is not affected.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            OnboardingStore.shared.clearPersonalInformation()
            ClaimTrackingStore.shared.clearAll()
            UpcomingSettlementWatchStore.shared.clearAll()
            NotificationManager.shared.clearPersonalInformation()
            MatchProfileRefresh.rescanCachedCatalog()
            self?.rebuildContentWithoutAnimation()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }
}

// MARK: - Match Profile summary

final class MatchingPreferencesViewController: UIViewController {
    private let scrollView = EdgeFadingScrollView()
    private let stack = UIStackView()
    private var hasAppeared = false

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Match Profile"
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(editTapped))
        navigationItem.rightBarButtonItem?.tintColor = DesignSystem.Color.brandGreen
        configureLayout()
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if hasAppeared {
            UIView.performWithoutAnimation { rebuild() }
        }
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureLayout() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.fadeLength = 28
        scrollView.fadesTopEdge = true
        scrollView.fadesBottomEdge = true
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16))
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
        }
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let draft = OnboardingStore.shared.draft

        let intro = UIView()
        let heading = UILabel()
        heading.text = "Your matching preferences"
        heading.font = .appBoldFont(size: 20)
        let body = UILabel()
        body.applyAppText(
            "We use these answers to find settlements that\nmay be relevant to you.",
            font: .appMediumFont(size: 16),
            color: UIColor.black.withAlphaComponent(0.70),
            lineHeight: 24
        )
        body.numberOfLines = 0
        intro.addSubview(heading)
        intro.addSubview(body)
        heading.snp.makeConstraints { make in make.top.leading.trailing.equalToSuperview() }
        body.snp.makeConstraints { make in
            make.top.equalTo(heading.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
        stack.addArrangedSubview(intro)
        stack.setCustomSpacing(24, after: intro)

        stack.addArrangedSubview(PreferenceSummaryCard(
            symbol: "building.2",
            color: DesignSystem.Color.brandGreen,
            title: "Companies & services",
            values: fullValues(draft.selectedCompanies.map(\.rawValue).sorted())
        ))
        stack.addArrangedSubview(PreferenceSummaryCard(
            symbol: "tag",
            color: DesignSystem.Color.brandGreen,
            title: "Categories",
            values: fullValues(SettlementCategoryCatalog.ordered(draft.selectedCategories))
        ))
        stack.addArrangedSubview(PreferenceSummaryCard(
            symbol: "calendar",
            color: DesignSystem.Color.brandGreen,
            title: "Time periods",
            values: fullValues(draft.selectedTimePeriods.map(\.rawValue).sorted())
        ))

        let valuesCard = UIView()
        valuesCard.backgroundColor = DesignSystem.Color.cardFill
        valuesCard.layer.cornerRadius = 16
        valuesCard.layer.borderWidth = 1
        valuesCard.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        valuesCard.clipsToBounds = true
        let valuesStack = UIStackView()
        valuesStack.axis = .vertical
        valuesCard.addSubview(valuesStack)
        valuesStack.snp.makeConstraints { $0.edges.equalToSuperview() }
        let notice = SettingsRowControl(symbol: "envelope", symbolColor: DesignSystem.Color.iconBlue, title: "Notices received", detail: draft.noticeAnswer?.rawValue ?? "No info")
        let proof = SettingsRowControl(symbol: "text.document", symbolColor: DesignSystem.Color.iconBlue, title: "Receipts or proof", detail: draft.proofAnswer?.rawValue ?? "No info")
        valuesStack.addArrangedSubview(notice)
        let sep = UIView(); sep.backgroundColor = UIColor.black.withAlphaComponent(0.10); valuesStack.addArrangedSubview(sep); sep.snp.makeConstraints { $0.height.equalTo(1) }
        valuesStack.addArrangedSubview(proof)
        stack.addArrangedSubview(valuesCard)
        stack.setCustomSpacing(24, after: valuesCard)

        let hint = HintView(symbolName: "checkmark.shield.fill", text: "Your answers are used only to personalize\npotential matches.", tint: DesignSystem.Color.brandGreen)
        stack.addArrangedSubview(hint)
    }

    private func fullValues(_ values: [String]) -> [String] {
        values.isEmpty ? ["No info"] : values
    }

    @objc private func editTapped() {
        pushPreparedViewController(MatchingPreferencesEditViewController())
    }
}

// MARK: - Match Profile editor

fileprivate enum PreferenceField: CaseIterable {
    case companies, categories, timePeriods, notices, proof

    var title: String {
        switch self {
        case .companies: return "Companies & services"
        case .categories: return "Categories"
        case .timePeriods: return "Time periods"
        case .notices: return "Notices received"
        case .proof: return "Receipts or proof"
        }
    }

    var symbol: String {
        switch self {
        case .companies: return "building.2"
        case .categories: return "tag"
        case .timePeriods: return "calendar"
        case .notices: return "envelope"
        case .proof: return "text.document"
        }
    }

    var color: UIColor {
        switch self {
        case .notices, .proof: return DesignSystem.Color.iconBlue
        default: return DesignSystem.Color.brandGreen
        }
    }
}

final class MatchingPreferencesEditViewController: UIViewController {
    private let originalDraft: OnboardingDraft
    private let tempStore: OnboardingStore
    private let rowsStack = UIStackView()
    private let footer = UIView()
    private var committed = false
    private var hasAppeared = false

    init() {
        let original = OnboardingStore.shared.draft
        self.originalDraft = original
        self.tempStore = OnboardingStore(initialDraft: original)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Edit Match Profile"
        navigationItem.hidesBackButton = false
        navigationItem.leftBarButtonItem = nil
        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        configureUI()
        rebuildRows()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if hasAppeared {
            UIView.performWithoutAnimation { rebuildRows() }
        }
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent && !committed { restoreOriginalProfile() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureUI() {
        let card = UIView()
        card.backgroundColor = DesignSystem.Color.cardFill
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        card.clipsToBounds = true
        rowsStack.axis = .vertical
        card.addSubview(rowsStack)
        rowsStack.snp.makeConstraints { $0.edges.equalToSuperview() }

        footer.backgroundColor = UIColor.white.withAlphaComponent(0.74)
        footer.layer.cornerRadius = 16
        footer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        footer.layer.borderWidth = 0.5
        footer.layer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        let save = PrimaryButton()
        save.setTitle("Save Changes", for: .normal)
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        let helper = UILabel()
        helper.text = "Updates will refine your potential matches."
        helper.font = .appMediumFont(size: 14)
        helper.textColor = UIColor.black.withAlphaComponent(0.50)
        helper.textAlignment = .center
        footer.addSubview(save)
        footer.addSubview(helper)

        view.addSubview(card)
        view.addSubview(footer)
        card.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        footer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        save.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        helper.snp.makeConstraints { make in
            make.top.equalTo(save.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(8)
            make.height.equalTo(17)
        }
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { rowsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, field) in PreferenceField.allCases.enumerated() {
            let row = SettingsRowControl(
                symbol: field.symbol,
                symbolColor: field.color,
                title: field.title,
                detail: detail(for: field),
                showsChevron: true
            )
            row.tag = index
            row.addTarget(self, action: #selector(fieldTapped(_:)), for: .touchUpInside)
            rowsStack.addArrangedSubview(row)
            if index < PreferenceField.allCases.count - 1 {
                let sep = UIView(); sep.backgroundColor = UIColor.black.withAlphaComponent(0.10)
                rowsStack.addArrangedSubview(sep); sep.snp.makeConstraints { $0.height.equalTo(1) }
            }
        }
    }

    private func detail(for field: PreferenceField) -> String {
        let draft = tempStore.draft
        switch field {
        case .companies: return draft.selectedCompanies.isEmpty ? "No info" : "\(draft.selectedCompanies.count) selected"
        case .categories: return draft.selectedCategories.isEmpty ? "No info" : "\(draft.selectedCategories.count) selected"
        case .timePeriods: return draft.selectedTimePeriods.isEmpty ? "No info" : "\(draft.selectedTimePeriods.count) selected"
        case .notices: return draft.noticeAnswer?.rawValue ?? "No info"
        case .proof: return draft.proofAnswer?.rawValue ?? "No info"
        }
    }

    @objc private func fieldTapped(_ sender: UIControl) {
        guard PreferenceField.allCases.indices.contains(sender.tag) else { return }
        let field = PreferenceField.allCases[sender.tag]
        let editor = PreferenceStepEditorViewController(field: field, store: tempStore)
        editor.onSaved = { [weak self] in
            self?.applyTemporaryProfileToSharedAndRefreshIfNeeded()
            self?.rebuildRows()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func applyTemporaryProfileToSharedAndRefreshIfNeeded() {
        let before = OnboardingStore.shared.draft
        let edited = tempStore.draft
        let affectsMatching = before.selectedCompanies != edited.selectedCompanies || before.selectedCategories != edited.selectedCategories

        OnboardingStore.shared.update { draft in
            draft.selectedCompanies = edited.selectedCompanies
            draft.selectedCategories = edited.selectedCategories
            draft.selectedTimePeriods = edited.selectedTimePeriods
            draft.noticeAnswer = edited.noticeAnswer
            draft.proofAnswer = edited.proofAnswer
        }
        if affectsMatching { MatchProfileRefresh.rescanCachedCatalog() }
    }

    private func restoreOriginalProfile() {
        let current = OnboardingStore.shared.draft
        let affectsMatching = current.selectedCompanies != originalDraft.selectedCompanies || current.selectedCategories != originalDraft.selectedCategories
        OnboardingStore.shared.update { draft in
            draft.selectedCompanies = originalDraft.selectedCompanies
            draft.selectedCategories = originalDraft.selectedCategories
            draft.selectedTimePeriods = originalDraft.selectedTimePeriods
            draft.noticeAnswer = originalDraft.noticeAnswer
            draft.proofAnswer = originalDraft.proofAnswer
        }
        if affectsMatching { MatchProfileRefresh.rescanCachedCatalog() }
    }

    @objc private func cancelTapped() {
        restoreOriginalProfile()
        committed = true
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        applyTemporaryProfileToSharedAndRefreshIfNeeded()
        committed = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - Single onboarding-style preference editor

fileprivate final class PreferenceStepEditorViewController: UIViewController {
    var onSaved: (() -> Void)?

    private let field: PreferenceField
    private let store: OnboardingStore
    private let originalDraft: OnboardingDraft
    private let stepView: OnboardingStepView
    private let saveButton = PrimaryButton()
    private var didSave = false

    init(field: PreferenceField, store: OnboardingStore) {
        self.field = field
        self.store = store
        self.originalDraft = store.draft
        switch field {
        case .companies: self.stepView = CompaniesStepView(store: store, resetSelectionOnInit: false)
        case .categories: self.stepView = CategoriesStepView(store: store)
        case .timePeriods: self.stepView = TimePeriodsStepView(store: store)
        case .notices: self.stepView = NoticesQuestionStepView(store: store)
        case .proof: self.stepView = ProofQuestionStepView(store: store)
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = field.title
        navigationItem.backButtonDisplayMode = .minimal
        saveButton.setTitle("Save", for: .normal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        view.addSubview(stepView)
        view.addSubview(saveButton)
        stepView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(saveButton.snp.top).offset(-16)
        }
        saveButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(16)
        }
        stepView.prepareForPresentation()
        UIView.performWithoutAnimation {
            stepView.alpha = 1
            stepView.transform = .identity
            stepView.animationTargets.forEach { $0.alpha = 1; $0.transform = .identity }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent && !didSave { restoreField() }
    }

    private func restoreField() {
        store.update { draft in
            switch field {
            case .companies: draft.selectedCompanies = originalDraft.selectedCompanies
            case .categories: draft.selectedCategories = originalDraft.selectedCategories
            case .timePeriods: draft.selectedTimePeriods = originalDraft.selectedTimePeriods
            case .notices: draft.noticeAnswer = originalDraft.noticeAnswer
            case .proof: draft.proofAnswer = originalDraft.proofAnswer
            }
        }
    }

    @objc private func saveTapped() {
        didSave = true
        onSaved?()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        navigationController?.popViewController(animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}

// MARK: - State editor

final class StateSettingsViewController: UIViewController {
    private let tempStore = OnboardingStore(initialDraft: OnboardingStore.shared.draft)
    private let searchField = SearchField()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let scrollView = EdgeFadingScrollView()
    private let rowsStack = UIStackView()
    private let saveButton = PrimaryButton()
    private var states = StateSelectionStepView.allStates

    override func loadView() { view = SoftBackgroundView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "State"
        navigationItem.hidesBackButton = false
        navigationItem.rightBarButtonItem = nil
        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        configureUI()
        rebuildRows(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureUI() {
        titleLabel.applyAppText("What state do you\ncurrently live in?", font: .appBoldFont(size: 32), color: .black, lineHeight: 38)
        titleLabel.numberOfLines = 2
        subtitleLabel.applyAppText("We’ll show settlement available in your state.", font: .appMediumFont(size: 16), color: DesignSystem.Color.textSecondary, lineHeight: 24)
        subtitleLabel.numberOfLines = 0
        rowsStack.axis = .vertical
        rowsStack.spacing = 12
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.fadeLength = 28
        scrollView.fadesTopEdge = true
        scrollView.fadesBottomEdge = true
        saveButton.setTitle("Save", for: .normal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        [searchField, titleLabel, subtitleLabel, scrollView, saveButton].forEach(view.addSubview)
        scrollView.addSubview(rowsStack)
        searchField.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        saveButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(16)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(saveButton.snp.top).offset(-16)
        }
        rowsStack.snp.makeConstraints { make in
            make.top.bottom.equalTo(scrollView.contentLayoutGuide).inset(0)
            make.leading.trailing.equalTo(scrollView.contentLayoutGuide).inset(16)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
        }

        searchField.textDidChange = { [weak self] query in
            guard let self else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            self.states = trimmed.isEmpty
                ? StateSelectionStepView.allStates
                : StateSelectionStepView.allStates.filter { $0.localizedCaseInsensitiveContains(trimmed) }
            self.rebuildRows(animated: true)
        }
    }

    private func rebuildRows(animated: Bool) {
        rowsStack.arrangedSubviews.forEach { rowsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for state in states {
            let row = SelectableRowView(title: state)
            row.isSelected = tempStore.draft.selectedStates.contains(state)
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let self, let row else { return }
                let select = !row.isSelected
                row.isSelected = select
                self.tempStore.update { draft in
                    if select { draft.selectedStates.insert(state) }
                    else { draft.selectedStates.remove(state) }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }, for: .touchUpInside)
            rowsStack.addArrangedSubview(row)
        }
        if animated, view.window != nil { animateCardEntrance(Array(rowsStack.arrangedSubviews.prefix(7))) }
    }

    @objc private func saveTapped() {
        let oldStates = OnboardingStore.shared.draft.selectedStates
        let newStates = tempStore.draft.selectedStates
        OnboardingStore.shared.update { $0.selectedStates = newStates }
        if oldStates != newStates { MatchProfileRefresh.rescanCachedCatalog() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - Settings components

private final class PremiumSettingsBanner: UIControl {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignSystem.Color.selectedCardFill
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.brandGreen.cgColor
        clipsToBounds = true

        let eyebrow = UILabel()
        eyebrow.text = "OWEDLY PREMIUM"
        eyebrow.font = .appMediumFont(size: 12)
        eyebrow.textColor = DesignSystem.Color.brandGreen
        let title = UILabel()
        title.text = "Unlock all your matches"
        title.font = .appSemiBoldFont(size: 20)
        let body = UILabel()
        body.applyAppText("See every potential match, get deadline\nalerts, and track your claims.", font: .appRegularFont(size: 14), color: .black, lineHeight: 17)
        body.numberOfLines = 2
        let sparkle = UIImageView(image: UIImage(systemName: "sparkles"))
        sparkle.tintColor = DesignSystem.Color.brandGreen
        sparkle.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        let button = UILabel()
        button.text = "View Plans"
        button.textAlignment = .center
        button.font = .appSemiBoldFont(size: 16)
        button.textColor = .white
        button.backgroundColor = DesignSystem.Color.brandGreen
        button.layer.cornerRadius = 12
        button.clipsToBounds = true

        [eyebrow, title, body, sparkle, button].forEach(addSubview)
        eyebrow.snp.makeConstraints { make in make.top.equalToSuperview().offset(12); make.leading.equalToSuperview().offset(16) }
        title.snp.makeConstraints { make in make.top.equalTo(eyebrow.snp.bottom).offset(8); make.leading.equalTo(eyebrow) }
        body.snp.makeConstraints { make in make.top.equalTo(title.snp.bottom).offset(8); make.leading.equalTo(eyebrow); make.trailing.lessThanOrEqualTo(sparkle.snp.leading).offset(-8) }
        sparkle.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.top.equalToSuperview().offset(20); make.size.equalTo(48) }
        button.snp.makeConstraints { make in
            make.top.equalTo(body.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(44)
            make.bottom.equalToSuperview().inset(12)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SettingsRowControl: UIControl {
    init(
        symbol: String,
        symbolColor: UIColor,
        title: String,
        detail: String? = nil,
        showsChevron: Bool = false,
        accessoryView: UIView? = nil
    ) {
        super.init(frame: .zero)
        backgroundColor = .clear
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = symbolColor
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentMode = .scaleAspectFit
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .appMediumFont(size: 16)
        titleLabel.textColor = .black
        addSubview(icon)
        addSubview(titleLabel)
        icon.snp.makeConstraints { make in make.leading.equalToSuperview().offset(16); make.centerY.equalToSuperview(); make.width.equalTo(26); make.height.equalTo(24) }
        titleLabel.snp.makeConstraints { make in make.leading.equalTo(icon.snp.trailing).offset(8); make.centerY.equalToSuperview() }

        var trailingAnchorView: UIView?
        if let accessoryView {
            addSubview(accessoryView)
            accessoryView.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.centerY.equalToSuperview() }
            trailingAnchorView = accessoryView
        } else if showsChevron {
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = UIColor.black.withAlphaComponent(0.58)
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            addSubview(chevron)
            chevron.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.centerY.equalToSuperview(); make.width.equalTo(12); make.height.equalTo(19) }
            trailingAnchorView = chevron
        }
        if let detail {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .appRegularFont(size: 14)
            detailLabel.textColor = UIColor.black.withAlphaComponent(0.60)
            detailLabel.textAlignment = .right
            detailLabel.adjustsFontSizeToFitWidth = true
            detailLabel.minimumScaleFactor = 0.8
            addSubview(detailLabel)
            detailLabel.snp.makeConstraints { make in
                make.centerY.equalToSuperview()
                if let trailingAnchorView {
                    make.trailing.equalTo(trailingAnchorView.snp.leading).offset(-12)
                } else {
                    make.trailing.equalToSuperview().inset(16)
                }
                make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(10)
            }
        } else if let trailingAnchorView {
            titleLabel.snp.makeConstraints { make in make.trailing.lessThanOrEqualTo(trailingAnchorView.snp.leading).offset(-10) }
        }
        snp.makeConstraints { $0.height.equalTo(56) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PreferenceChipView: UIView {
    init(text: String) {
        super.init(frame: .zero)

        backgroundColor = .white
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor
        clipsToBounds = true

        let label = UILabel()
        label.text = text
        label.font = .appMediumFont(size: 12)
        label.textColor = text == "No info" ? UIColor.black.withAlphaComponent(0.60) : .black
        label.textAlignment = .center
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(label)

        label.snp.makeConstraints { make in
            // Real constraints instead of leading/trailing whitespace in the label text. This
            // guarantees the same visible inset on both sides for every chip.
            make.leading.trailing.equalToSuperview().inset(9)
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(24) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PreferenceSummaryCard: UIView {
    init(symbol: String, color: UIColor, title: String, values: [String]) {
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.cardFill
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        clipsToBounds = true

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = color
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .appMediumFont(size: 16)

        let chipScrollView = HorizontalEdgeFadingScrollView()
        chipScrollView.showsHorizontalScrollIndicator = false
        chipScrollView.alwaysBounceHorizontal = false
        chipScrollView.clipsToBounds = true
        chipScrollView.fadeLength = 16

        let chips = UIStackView()
        chips.axis = .horizontal
        chips.spacing = 6
        chips.alignment = .center

        for value in values {
            chips.addArrangedSubview(PreferenceChipView(text: value))
        }

        [icon, titleLabel, chipScrollView].forEach(addSubview)
        chipScrollView.addSubview(chips)

        icon.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.leading.equalToSuperview().offset(16)
            make.size.equalTo(24)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(icon)
            make.leading.equalTo(icon.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(16)
        }
        chipScrollView.snp.makeConstraints { make in
            make.top.equalTo(icon.snp.bottom).offset(12)
            // The first chip starts exactly at the title's leading edge; the visible viewport
            // ends at the card's standard 16pt trailing inset.
            make.leading.equalTo(titleLabel.snp.leading)
            make.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(15)
            make.height.equalTo(24)
        }
        chips.snp.makeConstraints { make in
            make.edges.equalTo(chipScrollView.contentLayoutGuide)
            make.height.equalTo(chipScrollView.frameLayoutGuide)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
