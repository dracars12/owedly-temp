import UIKit
import SnapKit

private final class SettlementSearchTextField: UITextField {
    /// Keep UIKit's native compact clear button, but give it the same comfortable
    /// trailing breathing room as the State search field (whose text field itself
    /// ends 16 pt before the outer pill).
    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.clearButtonRect(forBounds: bounds)
        rect.origin.x -= 16
        return rect
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.editingRect(forBounds: bounds)
        rect.size.width = max(0, rect.width - 16)
        return rect
    }
}

final class SettlementSearchViewController: UIViewController, UITextFieldDelegate {
    private let searchField = SettlementSearchTextField()
    private let tableView = FadeTableView(frame: .zero, style: .plain)
    private let allSettlements: [Settlement]
    private var results: [Settlement] = []
    private var animatedResultIDs = Set<String>()

    init(settlements: [Settlement]) {
        self.allSettlements = settlements
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SoftBackgroundView()
        overrideUserInterfaceStyle = .light
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureNavigationBarAppearance()
        configureUI()
        DispatchQueue.main.async { [weak self] in self?.searchField.becomeFirstResponder() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        configureNavigationBarAppearance()
        updateResults(for: searchField.text ?? "")
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.updateGradient()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func configureNavigationBar() {
        navigationItem.title = "Search"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = nil
    }

    private func configureNavigationBarAppearance() {
        guard let bar = navigationController?.navigationBar else { return }
        navigationController?.view.overrideUserInterfaceStyle = .light
        bar.overrideUserInterfaceStyle = .light
        bar.prefersLargeTitles = false
        bar.barStyle = .default
        bar.titleTextAttributes = [
            .font: UIFont.appSemiBoldFont(size: 16),
            .foregroundColor: UIColor.black
        ]

        if #available(iOS 26.0, *) { return }

        bar.tintColor = .black
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .font: UIFont.appSemiBoldFont(size: 16),
            .foregroundColor: UIColor.black
        ]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
    }

    private func configureUI() {
        searchField.delegate = self
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search settlements",
            attributes: [
                .font: UIFont.appRegularFont(size: 16),
                .foregroundColor: UIColor.black.withAlphaComponent(0.42)
            ]
        )
        searchField.returnKeyType = .done
        // Match the State search field: native compact clear button with UIKit's
        // built-in trailing inset instead of a custom 56pt accessory view.
        searchField.clearButtonMode = .whileEditing
        searchField.backgroundColor = .white
        searchField.layer.cornerRadius = 21.5
        searchField.clipsToBounds = true
        searchField.font = .appRegularFont(size: 16)
        searchField.textColor = .black
        searchField.tintColor = DesignSystem.Color.brandGreen
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        // 16 pt outer inset + a comfortable text gap on both sides of the field.
        let magnifierContainer = UIView(frame: CGRect(x: 0, y: 0, width: 56, height: 43))
        let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        magnifier.tintColor = .black
        magnifier.contentMode = .scaleAspectFit
        magnifier.frame = CGRect(x: 16, y: 11.5, width: 20, height: 20)
        magnifierContainer.addSubview(magnifier)
        searchField.leftView = magnifierContainer
        searchField.leftViewMode = .always

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SettlementOfferCell.self, forCellReuseIdentifier: SettlementOfferCell.reuseID)
        tableView.contentInset.bottom = 16

        view.addSubview(searchField)
        view.addSubview(tableView)

        searchField.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(43)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func updateResults(for searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            results = []
            animatedResultIDs.removeAll()
            tableView.reloadData()
            tableView.updateGradient()
            return
        }

        let trackedIDs = Set(ClaimTrackingStore.shared.allRecords.map(\.settlementID))
        results = allSettlements.filter { settlement in
            guard !trackedIDs.contains(settlement.id) else { return false }
            return [settlement.title, settlement.company, settlement.category, settlement.shortDescription, settlement.eligibilityDescription ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        animatedResultIDs.removeAll()
        tableView.reloadData()
        tableView.updateGradient()
    }

    @objc private func searchTextChanged() {
        updateResults(for: searchField.text ?? "")
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        updateResults(for: "")
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension SettlementSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 113 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettlementOfferCell.reuseID, for: indexPath) as! SettlementOfferCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? SettlementOfferCell, results.indices.contains(indexPath.row) else { return }
        let settlement = results[indexPath.row]
        guard animatedResultIDs.insert(settlement.id).inserted else { return }
        let delay = min(Double(indexPath.row) * 0.045, 0.24)
        cell.animateIn(delay: delay)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        showSettlementDetails(results[indexPath.row])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        tableView.updateGradient()
    }
}
