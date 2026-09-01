import UIKit
import SnapKit

final class DiscoverViewController: UIViewController {
    private enum Filter: Hashable {
        case all
        case upcoming
        case category(String)

        var title: String {
            switch self {
            case .all: return "All"
            case .upcoming: return "Upcoming"
            case .category(let value): return value
            }
        }
    }

    private struct SectionState {
        let contentOffsetY: CGFloat
        let visibleCount: Int
    }

    private let fixedHeader = UIView()
    private let headlineLabel = UILabel()
    private let searchButton = UIButton(type: .system)
    private var categoryCollection: UICollectionView!

    private let tableView = FadeTableView(frame: .zero, style: .plain)
    private let scrollingHeaderView = UIView()
    private let bannerHost = UIView()
    private let sectionTitleLabel = UILabel()
    private let emptyFooterView = UIView()
    private let emptyPlaceholderView = EmptySectionPlaceholderView()

    private var allSettlements: [Settlement] = []
    private var filteredSettlements: [Settlement] = []
    private var filters: [Filter] = []
    private var selectedFilter: Filter = .all
    private let pageSize = 20
    private var visibleCount = 20
    private var offerTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var initialCatalogTask: Task<Void, Never>?
    private let refreshControl = UIRefreshControl()
    private var animatedSettlementIDs = Set<String>()
    private var sectionStates: [Filter: SectionState] = [:]
    private var currentBannerHeight: CGFloat = 0
    private var currentScrollingHeaderHeight: CGFloat = 43
    private lazy var sectionSwipePan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSectionPan(_:)))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureUI()
        configureFilters()
        LimitedOfferManager.shared.startIfNeeded()
        loadCatalog()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(claimTrackingChanged),
            name: .owedlyClaimTrackingDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settlementScanDidUpdate),
            name: .owedlySettlementScanDidUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(purchaseEntitlementChanged),
            name: .owedlyPurchaseEntitlementDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(purchaseStorefrontChanged),
            name: .owedlyPurchaseStorefrontDidChange,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBarAppearance()
        if let latest = SettlementScanner.shared.latestResult {
            applyCatalog(latest.allSettlements, preserveSectionStates: true)
        } else {
            rebuildBanner()
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Persist the *actual* position right before Discover is covered (details, another tab,
        // full-screen offer, etc.). This is a final safety net in addition to live scroll-state
        // tracking, so returning from a detail screen can never resurrect an older pagination
        // offset captured when the user was farther down the list.
        captureCurrentSectionState()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableBottomInset()
        updateScrollingHeaderFrame()
        updateEmptyFooterFrameIfNeeded()
        tableView.updateGradient()
        updateTabBarMaterialForCurrentScrollPosition()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    deinit {
        NotificationCenter.default.removeObserver(self)
        offerTimer?.invalidate()
        refreshTask?.cancel()
        initialCatalogTask?.cancel()
    }

    private func updateTabBarMaterialForCurrentScrollPosition() {
        (tabBarController as? MainTabBarController)?.updateBottomBarAppearance(for: tableView)
    }

    private func configureNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = nil
        navigationItem.backButtonDisplayMode = .minimal

        let titleLabel = UILabel()
        titleLabel.text = "Discover"
        titleLabel.font = .appMediumFont(size: 20)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.sizeToFit()

        let titleItem = UIBarButtonItem(customView: titleLabel)
        if #available(iOS 26.0, *) {
            // Keep the leading title in the navigation bar, but explicitly opt it out of
            // Liquid Glass. Only actionable navigation items should look like controls.
            titleItem.hidesSharedBackground = true
            titleItem.sharesBackground = false
        }
        navigationItem.leftBarButtonItem = titleItem
        navigationItem.rightBarButtonItem = makeSettingsBarButtonItem()
    }

    private func makeSettingsBarButtonItem() -> UIBarButtonItem {
        // Use the standard navigation-bar item again. On iOS 26 UIKit supplies the native
        // Liquid Glass treatment and press behavior automatically.
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settings.tintColor = .black
        return settings
    }

    private func configureNavigationBarAppearance() {
        guard let bar = navigationController?.navigationBar else { return }
        navigationController?.view.overrideUserInterfaceStyle = .light
        bar.overrideUserInterfaceStyle = .light
        bar.prefersLargeTitles = false
        bar.barStyle = .default
        bar.titleTextAttributes = [.foregroundColor: UIColor.black]

        // On iOS 26+ leave the bar material to UIKit so glass keeps rendering natively.
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

        headlineLabel.applyAppText(
            "Find settlements\nyou may qualify for",
            font: .appBoldFont(size: 32),
            color: DesignSystem.Color.textPrimary,
            lineHeight: 38
        )

        var searchConfig = UIButton.Configuration.plain()
        searchConfig.image = UIImage(systemName: "magnifyingglass")
        searchConfig.imagePadding = 6
        searchConfig.title = "Search settlements"
        searchConfig.baseForegroundColor = UIColor.black.withAlphaComponent(0.50)
        searchConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        searchButton.configuration = searchConfig
        searchButton.titleLabel?.font = .appRegularFont(size: 16)
        searchButton.contentHorizontalAlignment = .leading
        searchButton.backgroundColor = .white
        searchButton.layer.cornerRadius = 21.5
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
        layout.estimatedItemSize = .zero
        categoryCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        categoryCollection.backgroundColor = .clear
        categoryCollection.showsHorizontalScrollIndicator = false
        categoryCollection.alwaysBounceHorizontal = true
        categoryCollection.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        categoryCollection.dataSource = self
        categoryCollection.delegate = self
        categoryCollection.register(CategoryPillCell.self, forCellWithReuseIdentifier: CategoryPillCell.reuseID)

        [headlineLabel, searchButton, categoryCollection].forEach(fixedHeader.addSubview)

        headlineLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        searchButton.snp.makeConstraints { make in
            make.top.equalTo(headlineLabel.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(43)
        }
        categoryCollection.snp.makeConstraints { make in
            make.top.equalTo(searchButton.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(35)
            make.bottom.equalToSuperview().inset(12)
        }

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SettlementOfferCell.self, forCellReuseIdentifier: SettlementOfferCell.reuseID)
        tableView.contentInset.bottom = 16
        tableView.verticalScrollIndicatorInsets.bottom = 16
        tableView.addGestureRecognizer(sectionSwipePan)

        refreshControl.tintColor = DesignSystem.Color.brandGreen
        refreshControl.addTarget(self, action: #selector(refreshSettlements), for: .valueChanged)
        tableView.refreshControl = refreshControl

        if #available(iOS 26.0, *) {
            // The hierarchy also contains a horizontal category UICollectionView, so make the
            // vertical settlement table the explicit bottom-edge scroll source for bar material.
            setContentScrollView(tableView, for: .bottom)
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(fixedHeader.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        emptyFooterView.backgroundColor = .clear
        emptyFooterView.isUserInteractionEnabled = false
        emptyFooterView.addSubview(emptyPlaceholderView)
        emptyPlaceholderView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(28)
            make.trailing.lessThanOrEqualToSuperview().inset(28)
        }

        scrollingHeaderView.backgroundColor = .clear
        tableView.tableHeaderView = scrollingHeaderView

        sectionTitleLabel.text = "Settlement offers"
        sectionTitleLabel.font = .appSemiBoldFont(size: 16)
        sectionTitleLabel.textColor = DesignSystem.Color.textPrimary

        scrollingHeaderView.addSubview(bannerHost)
        scrollingHeaderView.addSubview(sectionTitleLabel)

        bannerHost.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(0)
        }
        sectionTitleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalToSuperview().offset(12)
        }

        rebuildBanner()
    }

    private func configureFilters() {
        syncFiltersWithProfile(resetSelection: true)
    }

    private func syncFiltersWithProfile(resetSelection: Bool) {
        let previous = selectedFilter
        var updated: [Filter] = [.all]

        // Always expose the complete category catalog in Discover. The user's onboarding choices
        // are simply promoted to the front so personalization is visible without hiding anything.
        let selectedSet = OnboardingStore.shared.draft.selectedCategories
        let selected = SettlementCategoryCatalog.ordered(selectedSet)
        let remaining = SettlementCategoryCatalog.all.filter { !selectedSet.contains($0) }
        let orderedSections = selected + remaining

        for section in orderedSections {
            if section == SettlementCategoryCatalog.upcoming {
                updated.append(.upcoming)
            } else {
                updated.append(.category(section))
            }
        }
        filters = updated
        if resetSelection || !filters.contains(previous) {
            selectedFilter = .all
        } else {
            selectedFilter = previous
        }
        categoryCollection.reloadData()
        if let index = filters.firstIndex(of: selectedFilter) {
            categoryCollection.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
        }
    }

    private func loadCatalog() {
        if let latest = SettlementScanner.shared.latestResult {
            applyCatalog(latest.allSettlements)
            return
        }

        // Render any local cache immediately, then validate freshness in the background.
        // This matters after scanner/schema updates: an old cache can be shown instantly while
        // .preferFreshCache automatically performs the one required live refresh.
        initialCatalogTask = Task { [weak self] in
            let cached = await SettlementDataManager.shared.fetchSettlements(policy: .cacheOnly)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.applyCatalog(cached.settlements)
            }

            let result = await SettlementScanner.shared.loadAndScan(refreshPolicy: .preferFreshCache)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.applyCatalog(result.allSettlements, preserveSectionStates: true)
                self.initialCatalogTask = nil
            }
        }
    }

    private func applyCatalog(_ settlements: [Settlement], preserveSectionStates: Bool = false) {
        syncFiltersWithProfile(resetSelection: false)
        let selectedCompanies = Set(
            OnboardingStore.shared.draft.selectedCompanies.map { Self.normalizedCompanyKey($0.rawValue) }
        )

        let trackedIDs = Set(ClaimTrackingStore.shared.allRecords.map(\.settlementID))

        allSettlements = settlements
            .filter { $0.status == .open || $0.status == .upcoming }
            .filter { !trackedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPreferred = Self.matchesSelectedCompany(lhs, selectedCompanies: selectedCompanies)
                let rhsPreferred = Self.matchesSelectedCompany(rhs, selectedCompanies: selectedCompanies)
                if lhsPreferred != rhsPreferred { return lhsPreferred && !rhsPreferred }
                return Self.catalogSort(lhs, rhs)
            }

        if !preserveSectionStates { sectionStates.removeAll() }
        applyFilter(resetPage: !preserveSectionStates)
    }

    private static func matchesSelectedCompany(_ settlement: Settlement, selectedCompanies: Set<String>) -> Bool {
        guard !selectedCompanies.isEmpty else { return false }
        let company = normalizedCompanyKey(settlement.company)
        if selectedCompanies.contains(company) { return true }

        let searchable = normalizedCompanyKey(settlement.title + " " + settlement.company)
        return selectedCompanies.contains { selected in
            selected.count >= 3 && searchable.contains(selected)
        }
    }

    private static func normalizedCompanyKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9&]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func catalogSort(_ lhs: Settlement, _ rhs: Settlement) -> Bool {
        if lhs.isFeatured != rhs.isFeatured { return lhs.isFeatured && !rhs.isFeatured }
        if lhs.sourceRank != rhs.sourceRank { return lhs.sourceRank < rhs.sourceRank }
        switch (lhs.deadline, rhs.deadline) {
        case let (l?, r?): return l < r
        case (.some, .none): return true
        default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func applyFilter(resetPage: Bool) {
        switch selectedFilter {
        case .all:
            filteredSettlements = allSettlements
        case .upcoming:
            filteredSettlements = allSettlements.filter { $0.status == .upcoming }
        case .category(let category):
            filteredSettlements = allSettlements.filter {
                $0.category.compare(category, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }

        let savedState = resetPage ? nil : sectionStates[selectedFilter]
        if resetPage {
            visibleCount = pageSize
            animatedSettlementIDs.removeAll()
        } else {
            visibleCount = max(pageSize, savedState?.visibleCount ?? pageSize)
        }

        sectionTitleLabel.text = selectedFilter == .upcoming ? "Upcoming offers" : "Settlement offers"
        rebuildBanner()
        tableView.reloadData()
        updateScrollingHeaderFrame()
        updateEmptyState()
        updateTabBarMaterialForCurrentScrollPosition()

        let desiredOffsetY = savedState?.contentOffsetY ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.restoreTableOffset(y: desiredOffsetY)
        }
    }

    private func captureCurrentSectionState() {
        let offsetY = max(0, tableView.contentOffset.y)
        sectionStates[selectedFilter] = SectionState(contentOffsetY: offsetY, visibleCount: visibleCount)
    }

    private func restoreTableOffset(y: CGFloat) {
        tableView.layoutIfNeeded()
        let minimumY = -tableView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        )
        let clampedY = min(max(y, minimumY), maximumY)
        tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        tableView.updateGradient()
    }

    private func updateEmptyState() {
        guard isCurrentSectionEmpty else {
            tableView.tableFooterView = nil
            return
        }

        let title = selectedFilter == .all ? "No settlements available yet" : "Nothing in this section yet"
        emptyPlaceholderView.configure(
            title: title,
            subtitle: "Try another section or check back after the next scan."
        )
        updateEmptyFooterFrameIfNeeded()
    }

    private func updateEmptyFooterFrameIfNeeded() {
        guard isCurrentSectionEmpty, tableView.bounds.width > 0, tableView.bounds.height > 0 else { return }
        let availableHeight = max(220, tableView.bounds.height - currentScrollingHeaderHeight - tableView.contentInset.bottom)
        let desiredFrame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: availableHeight)
        let frameChanged = emptyFooterView.frame != desiredFrame
        if frameChanged { emptyFooterView.frame = desiredFrame }

        if tableView.tableFooterView !== emptyFooterView || frameChanged {
            // Re-assigning after a size change asks UITableView to consume the new footer height.
            tableView.tableFooterView = emptyFooterView
        }
    }

    private func updateTableBottomInset() {
        let baseSpacing: CGFloat = 16
        guard let tabBar = tabBarController?.tabBar, !tabBar.isHidden, tabBar.window != nil else {
            if abs(tableView.contentInset.bottom - baseSpacing) > 0.5 {
                tableView.contentInset.bottom = baseSpacing
                tableView.verticalScrollIndicatorInsets.bottom = baseSpacing
            }
            return
        }

        let tabFrame = view.convert(tabBar.bounds, from: tabBar)
        let coveredHeight = max(0, view.bounds.maxY - tabFrame.minY)
        let bottomInset = max(baseSpacing, coveredHeight + baseSpacing)
        if abs(tableView.contentInset.bottom - bottomInset) > 0.5 {
            tableView.contentInset.bottom = bottomInset
            tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
    }

    private var visibleSettlements: ArraySlice<Settlement> {
        filteredSettlements.prefix(visibleCount)
    }

    private var isCurrentSectionEmpty: Bool { filteredSettlements.isEmpty }

    private func rebuildBanner() {
        offerTimer?.invalidate()
        bannerHost.subviews.forEach { $0.removeFromSuperview() }
        currentBannerHeight = 0

        let cachedOffer = PurchaseManager.shared.cachedSpecialOffer()
        let shouldShowOffer = !PurchaseManager.shared.isPurchased
            && LimitedOfferManager.shared.remaining() > 0
            && cachedOffer != nil
        var banner: UIView?
        if shouldShowOffer, let cachedOffer {
            let offer = LimitedOfferBannerView(offerInfo: cachedOffer)
            offer.onTap = { [weak self] in self?.presentLimitedOffer() }
            banner = offer
            currentBannerHeight = 123

            offerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak offer] timer in
                DispatchQueue.main.async {
                    guard let self, let offer else { timer.invalidate(); return }
                    let remaining = LimitedOfferManager.shared.remaining()
                    if remaining <= 0 {
                        timer.invalidate()
                        self.rebuildBanner()
                        return
                    }
                    offer.update(remaining: remaining)
                }
            }
        } else if let nearest = nearestDeadlineSettlement() {
            let deadline = DeadlineHeroView(settlement: nearest)
            deadline.onTap = { [weak self] in self?.openSettlementDetails(nearest) }
            banner = deadline
            currentBannerHeight = 244
        }

        if let banner {
            bannerHost.isHidden = false
            bannerHost.addSubview(banner)
            banner.snp.makeConstraints { $0.edges.equalToSuperview() }
        } else {
            bannerHost.isHidden = true
        }
        updateScrollingHeaderFrame()
    }

    private func nearestDeadlineSettlement() -> Settlement? {
        filteredSettlements
            .filter { $0.status == .open }
            .filter { ($0.deadline ?? .distantPast) > Date() }
            .min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    private func updateScrollingHeaderFrame() {
        let hasBanner = currentBannerHeight > 0

        bannerHost.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            if hasBanner {
                make.top.equalToSuperview().offset(12)
                make.height.equalTo(currentBannerHeight)
            } else {
                make.top.equalToSuperview()
                make.height.equalTo(0)
            }
        }
        sectionTitleLabel.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            if hasBanner {
                make.top.equalTo(bannerHost.snp.bottom).offset(28)
            } else {
                make.top.equalToSuperview().offset(12)
            }
        }

        currentScrollingHeaderHeight = hasBanner
            ? (12 + currentBannerHeight + 28 + 19 + 12)
            : (12 + 19 + 12)
        updateEmptyFooterFrameIfNeeded()

        let width = tableView.bounds.width
        guard width > 0 else { return }
        let height = currentScrollingHeaderHeight

        if abs(scrollingHeaderView.frame.height - height) > 0.5 || abs(scrollingHeaderView.frame.width - width) > 0.5 {
            scrollingHeaderView.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = scrollingHeaderView
        }
        scrollingHeaderView.setNeedsLayout()
        scrollingHeaderView.layoutIfNeeded()
    }



    @objc private func claimTrackingChanged() {
        if let latest = SettlementScanner.shared.latestResult {
            applyCatalog(latest.allSettlements, preserveSectionStates: true)
        } else {
            applyCatalog(allSettlements, preserveSectionStates: true)
        }
    }

    @objc private func settlementScanDidUpdate() {
        guard refreshTask == nil, initialCatalogTask == nil,
              let latest = SettlementScanner.shared.latestResult else { return }
        applyCatalog(latest.allSettlements, preserveSectionStates: true)
    }

    @objc private func refreshSettlements() {
        guard refreshTask == nil else { return }

        initialCatalogTask?.cancel()
        initialCatalogTask = nil
        captureCurrentSectionState()
        refreshTask = Task { [weak self] in
            // Pull-to-refresh re-runs local matching immediately, but a website refresh only
            // happens when the shared 24h cache is stale. This prevents user-driven request spam.
            let result = await SettlementScanner.shared.loadAndScan(refreshPolicy: .preferFreshCache)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.refreshControl.endRefreshing()
                self.applyCatalog(result.allSettlements, preserveSectionStates: true)
                self.refreshTask = nil
            }
        }
    }

    private func selectFilter(at index: Int) {
        guard filters.indices.contains(index), filters[index] != selectedFilter else { return }
        captureCurrentSectionState()
        selectedFilter = filters[index]
        categoryCollection.reloadData()
        let indexPath = IndexPath(item: index, section: 0)
        categoryCollection.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        applyFilter(resetPage: false)
    }

    @objc private func handleSectionPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, !refreshControl.isRefreshing,
              let currentIndex = filters.firstIndex(of: selectedFilter) else { return }

        let translation = gesture.translation(in: tableView)
        let velocity = gesture.velocity(in: tableView)
        let horizontalIntent = abs(translation.x) >= 52 || abs(velocity.x) >= 520
        guard horizontalIntent else { return }

        let directionX = abs(translation.x) >= 52 ? translation.x : velocity.x
        let targetIndex = directionX < 0 ? currentIndex + 1 : currentIndex - 1
        guard filters.indices.contains(targetIndex) else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        selectFilter(at: targetIndex)
    }

    @objc private func settingsTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pushPreparedViewController(SettingsViewController())
    }

    @objc private func purchaseEntitlementChanged() {
        rebuildBanner()
    }

    @objc private func purchaseStorefrontChanged() {
        rebuildBanner()
    }

    @objc private func searchTapped() {
        navigationItem.backButtonDisplayMode = .minimal
        let search = SettlementSearchViewController(settlements: allSettlements)
        navigationController?.pushViewController(search, animated: true)
    }

    private func loadMoreSettlementsIfNeeded(near index: Int) {
        guard !isCurrentSectionEmpty, visibleCount < filteredSettlements.count else { return }
        let currentVisible = min(visibleCount, filteredSettlements.count)
        guard index >= max(0, currentVisible - 5) else { return }

        let oldCount = currentVisible
        let newCount = min(oldCount + pageSize, filteredSettlements.count)
        guard newCount > oldCount else { return }
        visibleCount = newCount

        let paths = (oldCount..<newCount).map { IndexPath(row: $0, section: 0) }
        tableView.insertRows(at: paths, with: .none)
        sectionStates[selectedFilter] = SectionState(
            contentOffsetY: max(0, tableView.contentOffset.y),
            visibleCount: visibleCount
        )
    }

    private func openSettlementDetails(_ settlement: Settlement) {
        // Capture at the exact navigation moment as well. A user can scroll from deep in the list
        // back to the first rows and tap immediately; the saved state must represent that top
        // position, not the older offset recorded while pagination was expanding below.
        captureCurrentSectionState()
        showSettlementDetails(settlement)
    }

    private func presentLimitedOffer() {
        guard LimitedOfferManager.shared.remaining() > 0 else {
            rebuildBanner()
            return
        }
        let controller = LimitedOfferViewController()
        controller.modalPresentationStyle = .fullScreen
        controller.onFinished = { [weak self] in self?.rebuildBanner() }
        present(controller, animated: true)
    }
}

extension DiscoverViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isCurrentSectionEmpty ? 0 : visibleSettlements.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 113 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettlementOfferCell.reuseID, for: indexPath) as! SettlementOfferCell
        let settlement = Array(visibleSettlements)[indexPath.row]
        cell.configure(with: settlement)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isCurrentSectionEmpty else { return }
        openSettlementDetails(Array(visibleSettlements)[indexPath.row])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isCurrentSectionEmpty, let cell = cell as? SettlementOfferCell else { return }
        let settlements = Array(visibleSettlements)
        guard settlements.indices.contains(indexPath.row) else { return }
        let settlement = settlements[indexPath.row]

        // UI pagination is local: the website catalog has already been downloaded. Reveal the
        // next batch before the user actually hits the last visible row, even when this cell
        // has already been animated during an earlier visit to the section.
        DispatchQueue.main.async { [weak self] in
            self?.loadMoreSettlementsIfNeeded(near: indexPath.row)
        }

        guard animatedSettlementIDs.insert(settlement.id).inserted else { return }
        let delay = min(Double(indexPath.row) * 0.045, 0.24)
        cell.animateIn(delay: delay)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        tableView.updateGradient()
        updateTabBarMaterialForCurrentScrollPosition()

        // Keep each Discover section's state synchronized with the current visible position,
        // not only with the position that happened to be current when another page was loaded.
        // Previously load-more could save a deep offset; if the user then returned to the top and
        // opened a settlement, viewWillAppear restored that stale deep value on Back.
        captureCurrentSectionState()

        let threshold = scrollView.contentSize.height - scrollView.bounds.height - 260
        if scrollView.contentOffset.y > threshold {
            loadMoreSettlementsIfNeeded(near: max(0, min(visibleCount, filteredSettlements.count) - 1))
        }
    }
}

extension DiscoverViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { filters.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryPillCell.reuseID, for: indexPath) as! CategoryPillCell
        let filter = filters[indexPath.item]
        cell.configure(title: filter.title, selected: filter == selectedFilter)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let title = filters[indexPath.item].title
        let width = ceil((title as NSString).size(withAttributes: [.font: UIFont.appMediumFont(size: 14)]).width) + 26
        return CGSize(width: max(43, width), height: 35)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectFilter(at: indexPath.item)
    }
}

extension DiscoverViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === sectionSwipePan, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: tableView)
        return abs(velocity.x) > abs(velocity.y) * 1.25 && abs(velocity.x) > 180
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === sectionSwipePan || otherGestureRecognizer === sectionSwipePan
    }
}

private final class LimitedOfferBannerView: UIControl {
    var onTap: (() -> Void)?

    private let discount = UILabel()
    private let subtitle = UILabel()
    private let grab = UILabel()
    private let timerCard = UIView()
    private let timerCaption = UILabel()
    private let timerLabel = UILabel()

    init(offerInfo: SpecialOfferInfo) {
        super.init(frame: .zero)
        layer.cornerRadius = 16
        clipsToBounds = true
        backgroundColor = DesignSystem.Color.brandGreen

        if let percent = offerInfo.discountPercent {
            discount.text = "-\(percent)% OFF"
        } else {
            discount.text = "\(offerInfo.product.localizedPrice) / YEAR"
        }
        discount.font = .appHeavyFont(size: 28)
        discount.textColor = .white
        discount.adjustsFontSizeToFitWidth = true
        discount.minimumScaleFactor = 0.65
        subtitle.text = "Limited time offer"
        subtitle.font = .appMediumFont(size: 16)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.70)
        grab.text = "Grab this deal"
        grab.font = .appMediumFont(size: 14)
        grab.textColor = .black
        grab.backgroundColor = .white
        grab.layer.cornerRadius = 6
        grab.clipsToBounds = true
        grab.textAlignment = .center

        timerCard.backgroundColor = .white
        timerCard.layer.cornerRadius = 12
        timerCaption.text = "Offer ends in"
        timerCaption.font = .appSemiBoldFont(size: 12)
        timerCaption.textColor = DesignSystem.Color.textSecondary
        timerCaption.textAlignment = .center
        timerLabel.font = .appBoldFont(size: 36)
        timerLabel.textColor = .black
        timerLabel.textAlignment = .center
        timerLabel.adjustsFontSizeToFitWidth = true
        timerLabel.minimumScaleFactor = 0.8

        [discount, subtitle, grab, timerCard].forEach(addSubview)
        timerCard.addSubview(timerCaption)
        timerCard.addSubview(timerLabel)

        discount.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(17)
            make.top.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(timerCard.snp.leading).offset(-8)
        }
        subtitle.snp.makeConstraints { make in
            make.leading.equalTo(discount)
            make.top.equalTo(discount.snp.bottom).offset(4)
        }
        grab.snp.makeConstraints { make in
            make.leading.equalTo(discount)
            make.top.equalTo(subtitle.snp.bottom).offset(8)
            make.width.equalTo(107)
            make.height.equalTo(25)
        }
        timerCard.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview().inset(16)
            make.width.equalTo(147)
        }
        timerCaption.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.centerX.equalToSuperview()
        }
        timerLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(12)
        }
        snp.makeConstraints { $0.height.equalTo(123) }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        update(remaining: LimitedOfferManager.shared.remaining())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(remaining: TimeInterval) {
        let value = max(0, Int(ceil(remaining)))
        timerLabel.text = String(format: "%02d : %02d", value / 60, value % 60)
    }

    @objc private func tapped() { onTap?() }
}

private final class DeadlineHeroView: UIControl {
    var onTap: (() -> Void)?
    var badge: PaddingLabel!

    init(settlement: Settlement) {
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.brandGreen.withAlphaComponent(0.06)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.brandGreen.withAlphaComponent(0.50).cgColor
        clipsToBounds = true

        let title = UILabel()
        title.text = settlement.title
        title.font = .appBoldFont(size: 24)
        title.textColor = .black
        title.numberOfLines = 2
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.82

        let logoBox = UIView()
        logoBox.backgroundColor = .white
        logoBox.layer.cornerRadius = 12
        logoBox.layer.borderWidth = 1
        logoBox.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        logoBox.clipsToBounds = true
        let logo = UIImageView()
        logo.contentMode = .scaleAspectFill
        logo.clipsToBounds = true
        SettlementImageLoader.shared.load(settlement.imageURL, into: logo)

        let illustration = UIImageView(image: UIImage(named: "deadline_folder_illustration"))
        illustration.contentMode = .scaleAspectFit
        illustration.isUserInteractionEnabled = false

        badge = PaddingLabel()
        badge.text = "⌛ Closing soon"
        badge.font = .appMediumFont(size: 12)
        badge.textColor = UIColor.black.withAlphaComponent(0.60)
        badge.backgroundColor = UIColor(hex: 0xFAFEEF, alpha: 0.5)
        badge.textInsets = UIEdgeInsets(
            top: 8,
            left: 10,
            bottom: 8,
            right: 12
        )
        badge.layer.cornerRadius = 12
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor
        badge.clipsToBounds = true
        badge.textAlignment = .center

        let deadlineCaption = UILabel()
        deadlineCaption.text = "Deadline"
        deadlineCaption.font = .appMediumFont(size: 12)
        deadlineCaption.textColor = UIColor.black.withAlphaComponent(0.60)
        let deadline = UILabel()
        deadline.text = settlement.deadline.map { Self.dateFormatter.string(from: $0) } ?? "Not listed"
        deadline.font = .appMediumFont(size: 16)
        deadline.textColor = UIColor.black.withAlphaComponent(0.60)

        let button = UILabel()
        button.text = "View details"
        button.font = .appSemiBoldFont(size: 16)
        button.textColor = .white
        button.textAlignment = .center
        button.backgroundColor = DesignSystem.Color.brandGreen
        button.layer.cornerRadius = 12
        button.clipsToBounds = true

        [illustration, title, logoBox, badge, deadlineCaption, deadline, button].forEach(addSubview)
        logoBox.addSubview(logo)
        title.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(16)
            make.width.lessThanOrEqualTo(220)
        }
        logoBox.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(16)
            make.size.equalTo(44)
        }
        logo.snp.makeConstraints { $0.edges.equalToSuperview() }
        illustration.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(11)
            make.bottom.equalToSuperview().inset(11)
            make.width.equalTo(168)
            make.height.equalTo(168)
        }
        badge.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(title.snp.bottom).offset(12)
//            make.width.equalTo(111)
//            make.height.equalTo(24)
        }
        deadlineCaption.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(badge.snp.bottom).offset(12)
        }
        deadline.snp.makeConstraints { make in
            make.leading.equalTo(deadlineCaption)
            make.top.equalTo(deadlineCaption.snp.bottom).offset(4)
        }
        button.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().inset(17)
            make.width.equalTo(140)
            make.height.equalTo(43)
        }
        snp.makeConstraints { $0.height.equalTo(244) }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        badge.layer.cornerRadius = badge.bounds.height / 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { onTap?() }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d, yyyy"; return f
    }()
}

final class PaddingLabel: UILabel {

    var textInsets = UIEdgeInsets.zero {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize

        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}
