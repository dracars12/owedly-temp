import UIKit
import SnapKit

final class MyClaimsViewController: UIViewController {
    private enum Filter {
        case active
        case closed
    }

    private enum ActiveSection {
        case needsAction
        case tracking
    }

    private let fixedHeader = UIView()
    private let payoutTitleLabel = UILabel()
    private let payoutValueLabel = UILabel()
    private let filterStack = UIStackView()
    private let activeButton = UIButton(type: .system)
    private let closedButton = UIButton(type: .system)

    private let summaryCard = UIView()
    private let activeCountLabel = UILabel()
    private let needActionCountLabel = UILabel()

    private let tableView = FadeTableView(frame: .zero, style: .plain)
    private let emptyView = UIView()
    private let emptyIcon = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptySubtitleLabel = UILabel()
    private let emptyButton = PrimaryButton()

    private var selectedFilter: Filter = .active
    private var activeRecords: [TrackedClaim] = []
    private var needsActionRecords: [TrackedClaim] = []
    private var trackingRecords: [TrackedClaim] = []
    private var closedRecords: [TrackedClaim] = []
    private var animatedIDs = Set<String>()
    private var appliedCompactLayout: Bool?

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureNavigationBarAppearance()
        configureUI()
        reloadClaims(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(claimTrackingChanged),
            name: .owedlyClaimTrackingDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settlementScanDidUpdate),
            name: .owedlySettlementScanDidUpdate,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        configureNavigationBarAppearance()
        reloadClaims(animated: false)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()
        tableView.updateGradient()
        updateTabBarMaterialForCurrentScrollPosition()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func updateTabBarMaterialForCurrentScrollPosition() {
        let observedScrollView: UIScrollView? = tableView.isHidden ? nil : tableView
        (tabBarController as? MainTabBarController)?.updateBottomBarAppearance(for: observedScrollView)
    }

    private func configureNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = nil
        navigationItem.backButtonDisplayMode = .minimal

        let titleLabel = UILabel()
        titleLabel.text = "My Claims"
        titleLabel.font = .appMediumFont(size: 20)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.sizeToFit()

        let titleItem = UIBarButtonItem(customView: titleLabel)
        if #available(iOS 26.0, *) {
            titleItem.hidesSharedBackground = true
            titleItem.sharesBackground = false
        }
        navigationItem.leftBarButtonItem = titleItem

        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settings.tintColor = .black
        navigationItem.rightBarButtonItem = settings
    }

    private func configureNavigationBarAppearance() {
        guard let bar = navigationController?.navigationBar else { return }
        navigationController?.view.overrideUserInterfaceStyle = .light
        bar.overrideUserInterfaceStyle = .light
        bar.prefersLargeTitles = false
        bar.barStyle = .default
        bar.titleTextAttributes = [.foregroundColor: UIColor.black]

        if #available(iOS 26.0, *) { return }

        bar.tintColor = .black
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
    }

    private func configureUI() {
        fixedHeader.backgroundColor = .clear
        view.addSubview(fixedHeader)
        fixedHeader.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
        }

        payoutTitleLabel.text = "Estimated payout:"
        payoutTitleLabel.font = .appBoldFont(size: 24)
        payoutTitleLabel.textColor = DesignSystem.Color.textPrimary

        payoutValueLabel.font = .appBoldFont(size: 64)
        payoutValueLabel.textColor = DesignSystem.Color.brandGreen
        payoutValueLabel.adjustsFontSizeToFitWidth = true
        payoutValueLabel.minimumScaleFactor = 0.64
        payoutValueLabel.numberOfLines = 1

        filterStack.axis = .horizontal
        filterStack.alignment = .fill
        filterStack.distribution = .fillEqually
        filterStack.spacing = 8
        configureFilterButton(activeButton, title: "Active", action: #selector(activeTapped))
        configureFilterButton(closedButton, title: "Closed", action: #selector(closedTapped))
        filterStack.addArrangedSubview(activeButton)
        filterStack.addArrangedSubview(closedButton)

        fixedHeader.addSubview(payoutTitleLabel)
        fixedHeader.addSubview(payoutValueLabel)
        fixedHeader.addSubview(filterStack)

        payoutTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        payoutValueLabel.snp.makeConstraints { make in
            make.top.equalTo(payoutTitleLabel.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(76)
        }
        filterStack.snp.makeConstraints { make in
            make.top.equalTo(payoutValueLabel.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(35)
            make.bottom.equalToSuperview().inset(12)
        }

        summaryCard.backgroundColor = .white
        summaryCard.layer.cornerRadius = 16
        summaryCard.clipsToBounds = true
        view.addSubview(summaryCard)
        summaryCard.snp.makeConstraints { make in
            make.top.equalTo(fixedHeader.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(89)
        }

        let activeMetric = makeMetricView(valueLabel: activeCountLabel, caption: "Active claims")
        let needMetric = makeMetricView(valueLabel: needActionCountLabel, caption: "Need action")
        let divider = UIView()
        divider.backgroundColor = UIColor.black.withAlphaComponent(0.10)

        summaryCard.addSubview(activeMetric)
        summaryCard.addSubview(divider)
        summaryCard.addSubview(needMetric)

        activeMetric.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(summaryCard.snp.centerX)
        }
        divider.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(56)
        }
        needMetric.snp.makeConstraints { make in
            make.leading.equalTo(summaryCard.snp.centerX)
            make.trailing.top.bottom.equalToSuperview()
        }

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.alwaysBounceVertical = true
        tableView.isFadeEnabled = true
        tableView.topFadeThreshold = 10
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MyClaimCell.self, forCellReuseIdentifier: MyClaimCell.reuseID)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 112, right: 0)
        tableView.verticalScrollIndicatorInsets.bottom = 112
        if #available(iOS 26.0, *) {
            setContentScrollView(tableView, for: .bottom)
        }
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(summaryCard.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        configureEmptyView()
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { make in
            make.top.equalTo(summaryCard.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(50)
        }

        applyFilterAppearance()
    }

    private func updateResponsiveLayoutIfNeeded() {
        guard view.bounds.height > 0 else { return }
        let compact = view.bounds.height <= 760
        guard appliedCompactLayout != compact else { return }
        appliedCompactLayout = compact

        payoutTitleLabel.font = .appBoldFont(size: compact ? 20 : 24)
        payoutValueLabel.font = .appBoldFont(size: compact ? 52 : 64)
        emptyTitleLabel.font = .appSemiBoldFont(size: compact ? 20 : 24)
        emptySubtitleLabel.font = .appMediumFont(size: compact ? 14 : 16)
        emptyIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: compact ? 42 : 48,
            weight: .regular
        )

        payoutTitleLabel.snp.remakeConstraints { make in
            make.top.equalToSuperview().offset(compact ? 6 : 12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        payoutValueLabel.snp.remakeConstraints { make in
            make.top.equalTo(payoutTitleLabel.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(compact ? 58 : 76)
        }
        filterStack.snp.remakeConstraints { make in
            make.top.equalTo(payoutValueLabel.snp.bottom).offset(compact ? 8 : 16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(35)
            make.bottom.equalToSuperview().inset(compact ? 8 : 12)
        }
        summaryCard.snp.remakeConstraints { make in
            make.top.equalTo(fixedHeader.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(compact ? 78 : 89)
        }
        emptyView.snp.remakeConstraints { make in
            make.top.equalTo(summaryCard.snp.bottom).offset(compact ? 4 : 0)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 42 : 50)
        }
    }

    private func configureFilterButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .appMediumFont(size: 14)
        button.layer.cornerRadius = 17.5
        button.layer.borderWidth = 1
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeMetricView(valueLabel: UILabel, caption: String) -> UIView {
        let container = UIView()
        valueLabel.font = .appSemiBoldFont(size: 32)
        valueLabel.textColor = DesignSystem.Color.brandGreen
        valueLabel.textAlignment = .center

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = .appMediumFont(size: 14)
        captionLabel.textColor = UIColor.black.withAlphaComponent(0.60)
        captionLabel.textAlignment = .center

        container.addSubview(valueLabel)
        container.addSubview(captionLabel)
        valueLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview()
        }
        captionLabel.snp.makeConstraints { make in
            make.top.equalTo(valueLabel.snp.bottom).offset(2)
            make.leading.trailing.equalToSuperview()
        }
        return container
    }

    private func configureEmptyView() {
        emptyView.backgroundColor = .clear
        emptyIcon.image = UIImage(systemName: "text.document")
        emptyIcon.tintColor = DesignSystem.Color.brandGreen
        emptyIcon.contentMode = .scaleAspectFit
        emptyIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)

        emptyTitleLabel.font = .appSemiBoldFont(size: 24)
        emptyTitleLabel.textColor = DesignSystem.Color.textPrimary
        emptyTitleLabel.textAlignment = .center
        emptyTitleLabel.numberOfLines = 0

        emptySubtitleLabel.font = .appMediumFont(size: 16)
        emptySubtitleLabel.textColor = UIColor.black.withAlphaComponent(0.70)
        emptySubtitleLabel.textAlignment = .center
        emptySubtitleLabel.numberOfLines = 0

        emptyButton.setTitle("Go to Offers", for: .normal)
        emptyButton.addTarget(self, action: #selector(goToOffersTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [emptyIcon, emptyTitleLabel, emptySubtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 8
        emptyIcon.snp.makeConstraints { $0.size.equalTo(56) }

        let stack = UIStackView(arrangedSubviews: [textStack, emptyButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24
        emptyView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(-10)
            make.leading.trailing.equalToSuperview().inset(16)
        }
    }

    private func reloadClaims(animated: Bool) {
        activeRecords = ClaimTrackingStore.shared.activeRecords
        needsActionRecords = activeRecords.filter { $0.state == .needsAction }
        trackingRecords = activeRecords.filter { $0.state == .filed }
        closedRecords = ClaimTrackingStore.shared.expiredRecords

        payoutValueLabel.text = formattedEstimatedPayout(for: activeRecords)
        activeCountLabel.text = activeRecords.isEmpty ? "-" : "\(activeRecords.count)"
        needActionCountLabel.text = activeRecords.isEmpty ? "-" : "\(needsActionRecords.count)"

        applyFilterAppearance()
        updateEmptyState()

        if animated {
            UIView.transition(with: tableView, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.tableView.reloadData()
            }
        } else {
            tableView.reloadData()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.layoutIfNeeded()
            self.updateTabBarMaterialForCurrentScrollPosition()
        }
    }

    private func applyFilterAppearance() {
        styleFilterButton(activeButton, selected: selectedFilter == .active)
        styleFilterButton(closedButton, selected: selectedFilter == .closed)
    }

    private func styleFilterButton(_ button: UIButton, selected: Bool) {
        if selected {
            button.backgroundColor = DesignSystem.Color.brandGreen.withAlphaComponent(0.06)
            button.layer.borderColor = DesignSystem.Color.brandGreen.cgColor
            button.setTitleColor(DesignSystem.Color.brandGreen, for: .normal)
        } else {
            button.backgroundColor = .white
            button.layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor
            button.setTitleColor(UIColor.black.withAlphaComponent(0.60), for: .normal)
        }
    }

    private func updateEmptyState() {
        let isEmpty: Bool
        switch selectedFilter {
        case .active:
            isEmpty = activeRecords.isEmpty
            emptyTitleLabel.text = "There are no submitted claims\npending review"
            emptySubtitleLabel.text = "Submit your first claim"
            emptyButton.isHidden = false
        case .closed:
            isEmpty = closedRecords.isEmpty
            emptyTitleLabel.text = "No closed claims yet"
            emptySubtitleLabel.text = "Expired claims that weren’t filed will appear here."
            emptyButton.isHidden = true
        }
        emptyView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    private var visibleActiveSections: [ActiveSection] {
        var result: [ActiveSection] = []
        if !needsActionRecords.isEmpty { result.append(.needsAction) }
        if !trackingRecords.isEmpty { result.append(.tracking) }
        return result
    }

    private func activeSection(at index: Int) -> ActiveSection? {
        guard visibleActiveSections.indices.contains(index) else { return nil }
        return visibleActiveSections[index]
    }

    private func records(in section: Int) -> [TrackedClaim] {
        switch selectedFilter {
        case .active:
            switch activeSection(at: section) {
            case .needsAction: return needsActionRecords
            case .tracking: return trackingRecords
            case .none: return []
            }
        case .closed:
            return section == 0 ? closedRecords : []
        }
    }

    private func record(at indexPath: IndexPath) -> TrackedClaim {
        records(in: indexPath.section)[indexPath.row]
    }

    private func formattedEstimatedPayout(for records: [TrackedClaim]) -> String {
        let total = records.compactMap { estimatedPayoutValue(from: $0.payoutText) }.reduce(0, +)
        guard total > 0 else { return "$ 0" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return "$ \(formatter.string(from: NSNumber(value: total)) ?? "\(Int(total))")"
    }

    private func estimatedPayoutValue(from text: String?) -> Double? {
        guard var text = text?.lowercased(), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: ",", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"(?:\$\s*)?(\d+(?:\.\d+)?)\s*(k|m)?"#, options: []) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let values: [Double] = matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let raw = ns.substring(with: match.range(at: 1))
            guard var value = Double(raw) else { return nil }
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                switch ns.substring(with: match.range(at: 2)) {
                case "k": value *= 1_000
                case "m": value *= 1_000_000
                default: break
                }
            }
            return value
        }
        return values.max()
    }

    private func openDetails(for record: TrackedClaim) {
        showSettlementDetails(record.resolvedSettlement())
    }

    @objc private func activeTapped() {
        guard selectedFilter != .active else { return }
        selectedFilter = .active
        animatedIDs.removeAll()
        tableView.setContentOffset(.zero, animated: false)
        reloadClaims(animated: true)
    }

    @objc private func closedTapped() {
        guard selectedFilter != .closed else { return }
        selectedFilter = .closed
        animatedIDs.removeAll()
        tableView.setContentOffset(.zero, animated: false)
        reloadClaims(animated: true)
    }

    @objc private func claimTrackingChanged() {
        reloadClaims(animated: true)
    }

    @objc private func appDidBecomeActive() {
        // `viewWillAppear` covers normal tab reveals. This covers the important case where the app
        // returns from background while My Claims is already the selected tab, so its status and
        // payout summary can never stay frozen on pre-background data.
        guard isViewLoaded, view.window != nil else { return }
        reloadClaims(animated: false)
    }

    @objc private func settlementScanDidUpdate() {
        // Foreground refresh can finish asynchronously after didBecomeActive. Refresh once more when
        // the scanner publishes fresh settlement metadata so tracked claims use the newest status,
        // deadline and payout information without requiring a tab switch.
        guard isViewLoaded, view.window != nil else { return }
        reloadClaims(animated: true)
    }

    @objc private func goToOffersTapped() {
        tabBarController?.selectedIndex = 0
    }

    @objc private func settingsTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pushPreparedViewController(SettingsViewController())
    }
}

extension MyClaimsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        switch selectedFilter {
        case .active: return visibleActiveSections.count
        case .closed: return closedRecords.isEmpty ? 0 : 1
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records(in: section).count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        113
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MyClaimCell.reuseID, for: indexPath) as! MyClaimCell
        let record = record(at: indexPath)
        let kind: MyClaimCell.Kind
        if selectedFilter == .closed {
            kind = .closed
        } else {
            kind = record.state == .needsAction ? .needsAction : .tracking
        }
        cell.configure(record: record, kind: kind)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openDetails(for: record(at: indexPath))
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        records(in: section).isEmpty ? 0.01 : 51
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !records(in: section).isEmpty else { return nil }
        let container = UIView()
        container.backgroundColor = .clear
        let label = UILabel()
        label.font = .appSemiBoldFont(size: 16)
        label.textColor = DesignSystem.Color.textPrimary
        if selectedFilter == .closed {
            label.text = "Closed claims"
        } else {
            switch activeSection(at: section) {
            case .needsAction: label.text = "Need attention"
            case .tracking: label.text = "Tracking"
            case .none: return nil
            }
        }
        container.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }
        return container
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        tableView.updateGradient()
        if scrollView === tableView {
            updateTabBarMaterialForCurrentScrollPosition()
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let record = record(at: indexPath)
        guard animatedIDs.insert(record.settlementID).inserted, let cell = cell as? MyClaimCell else { return }
        cell.animateIn(delay: min(Double(indexPath.row), 5) * 0.035)
    }
}

private final class MyClaimCell: UITableViewCell {
    enum Kind {
        case needsAction
        case tracking
        case closed
    }

    static let reuseID = "MyClaimCell"

    private let surface = MaterialSurfaceView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let dot = UIView()
    private let statusLabel = UILabel()
    private let dateLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var representedImageURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        iconContainer.backgroundColor = .white
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.borderWidth = 1
        iconContainer.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        iconContainer.clipsToBounds = true
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true

        titleLabel.font = .appBoldFont(size: 16)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78

        dot.layer.cornerRadius = 4
        statusLabel.font = .appMediumFont(size: 14)
        dateLabel.font = .appMediumFont(size: 14)
        dateLabel.textColor = DesignSystem.Color.textSecondary
        dateLabel.adjustsFontSizeToFitWidth = true
        dateLabel.minimumScaleFactor = 0.82

        chevron.tintColor = UIColor.black.withAlphaComponent(0.60)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        contentView.addSubview(surface)
        surface.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        surface.addSubview(titleLabel)
        surface.addSubview(dot)
        surface.addSubview(statusLabel)
        surface.addSubview(dateLabel)
        surface.addSubview(chevron)

        surface.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(101)
        }
        iconContainer.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(16)
            make.size.equalTo(44)
        }
        iconView.snp.makeConstraints { $0.edges.equalToSuperview() }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconContainer.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-10)
        }
        dot.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(11)
            make.size.equalTo(8)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot.snp.trailing).offset(6)
            make.centerY.equalTo(dot)
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-8)
        }
        dateLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(statusLabel.snp.bottom).offset(6)
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-8)
        }
        chevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(17)
            make.centerY.equalToSuperview()
            make.width.equalTo(12)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedImageURL = nil
        // Let `configure` swap directly to cached artwork when possible. Forcing the compact
        // placeholder here can become visible for a frame while My Claims reloads on return.
        alpha = 1
        transform = .identity
        layer.removeAllAnimations()
    }

    func configure(record: TrackedClaim, kind: Kind) {
        titleLabel.text = record.title

        switch kind {
        case .needsAction:
            dot.backgroundColor = DesignSystem.Color.brandGreen
            statusLabel.textColor = DesignSystem.Color.brandGreen
            statusLabel.text = "Ready to file"
            dateLabel.text = record.deadline.map { "Deadline \(Self.dateFormatter.string(from: $0))" } ?? "Deadline not listed"
        case .tracking:
            dot.backgroundColor = DesignSystem.Color.brandGreen
            statusLabel.textColor = DesignSystem.Color.brandGreen
            statusLabel.text = record.payoutText?.isEmpty == false ? record.payoutText : "Claim submitted"
            let filedDate = record.filedAt ?? record.startedAt
            dateLabel.text = "Claimed \(Self.dateFormatter.string(from: filedDate))"
        case .closed:
            dot.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            statusLabel.textColor = UIColor.black.withAlphaComponent(0.55)
            statusLabel.text = "Expired"
            dateLabel.text = record.deadline.map { "Deadline \(Self.dateFormatter.string(from: $0))" } ?? "Filing period ended"
        }

        let tint = kind == .closed ? UIColor.black.withAlphaComponent(0.36) : DesignSystem.Color.brandGreen
        representedImageURL = record.imageURL
        guard let imageURL = record.imageURL else {
            SettlementImageLoader.shared.applyPlaceholder(to: iconView, tint: tint)
            return
        }
        if let cached = SettlementImageLoader.shared.cachedImage(for: imageURL) {
            SettlementImageLoader.shared.applyImage(cached, to: iconView)
            return
        }
        SettlementImageLoader.shared.applyPlaceholder(to: iconView, tint: tint)
        SettlementImageLoader.shared.image(for: imageURL) { [weak self] image in
            guard let self, self.representedImageURL == imageURL, let image else { return }
            SettlementImageLoader.shared.applyImage(image, to: self.iconView)
        }
    }

    func animateIn(delay: TimeInterval) {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.99, y: 0.99)
        UIView.animate(
            withDuration: DesignSystem.Animation.cardDuration,
            delay: delay,
            usingSpringWithDamping: 0.90,
            initialSpringVelocity: 0.12,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
