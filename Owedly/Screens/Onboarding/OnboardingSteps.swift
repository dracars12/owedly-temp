import UIKit
import SnapKit

class OnboardingStepView: UIView {
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let bodyView = UIView()

    private let titleText: String
    private let subtitleText: String
    private var subtitleTopConstraint: Constraint?
    private var bodyTopConstraint: Constraint?
    private var compactLayoutApplied = false

    var animationTargets: [UIView] { [] }

    /// Most onboarding steps can always continue. Question-style steps override this so the
    /// fixed footer CTA can stay hidden until the user has made an explicit choice.
    var requiresExplicitAnswerBeforeContinue: Bool { false }
    var isContinueAllowed: Bool { true }
    var onContinueAvailabilityChanged: ((Bool) -> Void)?

    init(title: String, subtitle: String) {
        titleText = title
        subtitleText = subtitle
        super.init(frame: .zero)

        titleLabel.numberOfLines = 0
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = DesignSystem.Color.textSecondary
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(bodyView)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        subtitleLabel.snp.makeConstraints { make in
            subtitleTopConstraint = make.top.equalTo(titleLabel.snp.bottom)
                .offset(DesignSystem.Layout.Onboarding.titleSubtitleSpacing).constraint
            make.leading.trailing.equalToSuperview()
        }
        bodyView.snp.makeConstraints { make in
            bodyTopConstraint = make.top.equalTo(subtitleLabel.snp.bottom)
                .offset(DesignSystem.Layout.Onboarding.sectionSpacing).constraint
            make.leading.trailing.bottom.equalToSuperview()
        }

        applyTypography(compact: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func attributed(_ text: String, font: UIFont, color: UIColor, lineHeight: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    fileprivate static func supportingAttributedText(_ text: String, compact: Bool = false) -> NSAttributedString {
        attributed(
            text,
            font: .appMediumFont(size: compact ? 15 : 16),
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 21 : DesignSystem.Layout.LineHeight.body16
        )
    }

    /// iPadOS can run an iPhone-only app inside a short compatibility/windowed scene.
    /// Keep the normal iPhone composition unchanged, but tighten the vertical rhythm whenever
    /// the actual view is short instead of making decisions from UIScreen.main.bounds.
    func setCompactLayout(_ compact: Bool) {
        guard compactLayoutApplied != compact else { return }
        compactLayoutApplied = compact
        applyTypography(compact: compact)
        subtitleTopConstraint?.update(offset: compact ? 6 : DesignSystem.Layout.Onboarding.titleSubtitleSpacing)
        bodyTopConstraint?.update(offset: compact ? 16 : DesignSystem.Layout.Onboarding.sectionSpacing)
        setNeedsLayout()
    }

    private func applyTypography(compact: Bool) {
        let titleFont = UIFont.appBoldFont(size: compact ? 28 : 32)
        titleLabel.font = titleFont
        titleLabel.attributedText = Self.attributed(
            titleText,
            font: titleFont,
            color: DesignSystem.Color.textPrimary,
            lineHeight: compact ? 33 : DesignSystem.Layout.LineHeight.title32
        )

        let subtitleFont = UIFont.appMediumFont(size: compact ? 15 : 16)
        subtitleLabel.font = subtitleFont
        subtitleLabel.attributedText = Self.attributed(
            subtitleText,
            font: subtitleFont,
            color: DesignSystem.Color.textSecondary,
            lineHeight: compact ? 21 : DesignSystem.Layout.LineHeight.body16
        )
    }

    func prepareForPresentation() {
        prepareCardEntrance(animationTargets)
    }

    func animateCards() {
        animatePreparedCardEntrance(animationTargets)
    }
}

final class StateSelectionStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let searchField = SearchField()
    private let scrollView = EdgeFadingScrollView()
    private let stackView = UIStackView()
    private var displayedStates: [String] = []

    override var animationTargets: [UIView] { Array(stackView.arrangedSubviews.prefix(8)) }

    static let allStates: [String] = [
        "California", "Florida", "New York", "Texas", "Illinois", "Washington", "Oregon",
        "Alabama", "Alaska", "Arizona", "Arkansas", "Colorado", "Connecticut", "Delaware",
        "District of Columbia", "Georgia", "Hawaii", "Idaho", "Indiana", "Iowa", "Kansas",
        "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey",
        "New Mexico", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Pennsylvania",
        "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Utah", "Vermont",
        "Virginia", "West Virginia", "Wisconsin", "Wyoming"
    ]

    init(store: OnboardingStore) {
        self.store = store
        super.init(
            title: "What state do you\ncurrently live in?",
            subtitle: "We’ll show settlement available in your state."
        )
        configure()
        show(Self.allStates, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true

        stackView.axis = .vertical
        stackView.spacing = DesignSystem.Layout.Onboarding.rowSpacing

        bodyView.addSubview(searchField)
        bodyView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        searchField.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(DesignSystem.Layout.Onboarding.searchToRowsSpacing)
            make.leading.trailing.bottom.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        searchField.textDidChange = { [weak self] query in
            self?.filter(query: query)
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        stackView.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.rowSpacing
        scrollView.snp.remakeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(compact ? 14 : DesignSystem.Layout.Onboarding.searchToRowsSpacing)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func filter(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? Self.allStates
            : Self.allStates.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        show(filtered, animated: true)
    }

    private func show(_ states: [String], animated: Bool) {
        displayedStates = states
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for state in states {
            let row = SelectableRowView(title: state)
            row.isSelected = store.draft.selectedStates.contains(state)
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let self, let row else { return }
                let willSelect = !row.isSelected
                row.isSelected = willSelect
                self.store.update { draft in
                    if willSelect { draft.selectedStates.insert(state) }
                    else { draft.selectedStates.remove(state) }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }, for: .touchUpInside)
            stackView.addArrangedSubview(row)
        }

        guard animated, window != nil else { return }
        stackView.layoutIfNeeded()
        animateCardEntrance(Array(stackView.arrangedSubviews.prefix(7)))
    }
}

final class CompaniesStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let grid = UIStackView()
    private var cards: [CompanyCardView] = []

    override var animationTargets: [UIView] { cards }

    init(store: OnboardingStore, resetSelectionOnInit: Bool = true) {
        self.store = store
        // Fresh onboarding starts unselected, while Settings reuses the same visual step and
        // must preserve the user's existing choices.
        if resetSelectionOnInit {
            store.update { $0.selectedCompanies.removeAll() }
        }
        super.init(
            title: "Which companies or\nservices have you used?",
            subtitle: "Select all that apply. This helps us find your first matches."
        )
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        grid.axis = .vertical
        grid.spacing = DesignSystem.Layout.Onboarding.companyRowSpacing
        bodyView.addSubview(grid)
        grid.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }

        let options = CompanyOption.allCases
        for rowIndex in 0..<3 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = DesignSystem.Layout.Onboarding.companyColumnSpacing
            row.distribution = .fillEqually

            for column in 0..<2 {
                let option = options[rowIndex * 2 + column]
                let card = CompanyCardView(option: option)
                card.isSelected = store.draft.selectedCompanies.contains(option)
                card.addAction(UIAction { [weak self, weak card] _ in
                    guard let self, let card else { return }
                    let willSelect = !card.isSelected
                    card.isSelected = willSelect
                    self.store.update { draft in
                        if willSelect { draft.selectedCompanies.insert(option) }
                        else { draft.selectedCompanies.remove(option) }
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }, for: .touchUpInside)
                cards.append(card)
                row.addArrangedSubview(card)
            }
            grid.addArrangedSubview(row)
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        grid.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.companyRowSpacing
        for row in grid.arrangedSubviews.compactMap({ $0 as? UIStackView }) {
            row.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.companyColumnSpacing
        }
    }
}

final class TimePeriodsStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let stack = UIStackView()
    private let note = UILabel()
    private var noteTopConstraint: Constraint?
    private var rows: [SelectableRowView] = []

    override var animationTargets: [UIView] { rows }

    init(store: OnboardingStore) {
        self.store = store
        super.init(
            title: "When have you used\nthese services?",
            subtitle: "Select all time periods that apply."
        )
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        stack.axis = .vertical
        stack.spacing = DesignSystem.Layout.Onboarding.rowSpacing
        bodyView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        for option in TimePeriodOption.allCases {
            let row = SelectableRowView(title: option.rawValue, selectionAppearance: .tinted)
            row.isSelected = store.draft.selectedTimePeriods.contains(option)
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let self, let row else { return }
                let willSelect = !row.isSelected
                row.isSelected = willSelect
                self.store.update { draft in
                    if willSelect { draft.selectedTimePeriods.insert(option) }
                    else { draft.selectedTimePeriods.remove(option) }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }, for: .touchUpInside)
            rows.append(row)
            stack.addArrangedSubview(row)
        }

        note.text = "This helps us compare eligibility periods."
        note.textColor = DesignSystem.Color.textSecondary
        note.font = .appMediumFont(size: 16)
        note.attributedText = OnboardingStepView.supportingAttributedText(note.text ?? "")
        bodyView.addSubview(note)
        note.snp.makeConstraints { make in
            noteTopConstraint = make.top.equalTo(stack.snp.bottom).offset(DesignSystem.Spacing.x24).constraint
            make.leading.trailing.equalToSuperview()
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        stack.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.rowSpacing
        noteTopConstraint?.update(offset: compact ? 14 : DesignSystem.Spacing.x24)
        note.attributedText = OnboardingStepView.supportingAttributedText(note.text ?? "", compact: compact)
    }
}

final class CategoriesStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let scrollView = EdgeFadingScrollView()
    private let stack = UIStackView()
    private var rows: [SelectableRowView] = []

    override var animationTargets: [UIView] { rows }

    init(store: OnboardingStore) {
        self.store = store
        super.init(
            title: "What types of\nsettlements are relevant\nto you?",
            subtitle: "Select all that apply."
        )
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive

        stack.axis = .vertical
        stack.spacing = DesignSystem.Layout.Onboarding.rowSpacing

        bodyView.addSubview(scrollView)
        scrollView.addSubview(stack)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        for option in SettlementCategoryCatalog.all {
            let row = SelectableRowView(title: option, selectionAppearance: .tinted)
            row.isSelected = store.draft.selectedCategories.contains(option)
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let self, let row else { return }
                let willSelect = !row.isSelected
                row.isSelected = willSelect
                self.store.update { draft in
                    if willSelect { draft.selectedCategories.insert(option) }
                    else { draft.selectedCategories.remove(option) }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }, for: .touchUpInside)
            rows.append(row)
            stack.addArrangedSubview(row)
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        stack.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.rowSpacing
    }
}

final class NoticesQuestionStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let stack = UIStackView()
    private let hint = HintView(
        symbolName: "envelope.open.fill",
        text: "Notices may arrive by email or mail.",
        tint: DesignSystem.Color.iconBlue
    )
    private var hintBottomConstraint: Constraint?
    private var hintTopConstraint: Constraint?
    private var rows: [(NoticeAnswer, SelectableRowView)] = []

    override var animationTargets: [UIView] { rows.map { $0.1 } }
    override var requiresExplicitAnswerBeforeContinue: Bool { true }
    override var isContinueAllowed: Bool { store.draft.noticeAnswer != nil }

    init(store: OnboardingStore) {
        self.store = store
        super.init(
            title: "Have you ever received\nsettlement or data\nbreach notices?",
            subtitle: "This may help us identify claims you’ve already heard about."
        )
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        stack.axis = .vertical
        stack.spacing = DesignSystem.Layout.Onboarding.rowSpacing
        bodyView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        for option in NoticeAnswer.allCases {
            let row = SelectableRowView(title: option.rawValue)
            row.isSelected = store.draft.noticeAnswer == option
            row.addAction(UIAction { [weak self] _ in self?.select(option) }, for: .touchUpInside)
            rows.append((option, row))
            stack.addArrangedSubview(row)
        }

        bodyView.addSubview(hint)
        hint.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            hintBottomConstraint = make.bottom.equalToSuperview().inset(DesignSystem.Layout.Onboarding.questionHintBottom).constraint
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            hintTopConstraint = make.top.greaterThanOrEqualTo(stack.snp.bottom).offset(DesignSystem.Spacing.x18).constraint
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        stack.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.rowSpacing
        hintBottomConstraint?.update(offset: compact ? -14 : -DesignSystem.Layout.Onboarding.questionHintBottom)
        hintTopConstraint?.update(offset: compact ? 12 : DesignSystem.Spacing.x18)
    }

    private func select(_ option: NoticeAnswer) {
        let shouldClear = store.draft.noticeAnswer == option
        store.update { $0.noticeAnswer = shouldClear ? nil : option }
        for (item, row) in rows { row.isSelected = !shouldClear && item == option }
        onContinueAvailabilityChanged?(isContinueAllowed)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

final class ProofQuestionStepView: OnboardingStepView {
    private let store: OnboardingStore
    private let stack = UIStackView()
    private let hint = HintView(
        symbolName: "text.document.fill",
        text: "You can review requirements before filing.",
        tint: DesignSystem.Color.iconBlue
    )
    private var hintBottomConstraint: Constraint?
    private var hintTopConstraint: Constraint?
    private var rows: [(ProofAnswer, SelectableRowView)] = []

    override var animationTargets: [UIView] { rows.map { $0.1 } }
    override var requiresExplicitAnswerBeforeContinue: Bool { true }
    override var isContinueAllowed: Bool { store.draft.proofAnswer != nil }

    init(store: OnboardingStore) {
        self.store = store
        super.init(
            title: "Do you usually keep\nreceipts, emails,\nor other proof?",
            subtitle: "Proof may be required for some claims, but not all."
        )
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        stack.axis = .vertical
        stack.spacing = DesignSystem.Layout.Onboarding.rowSpacing
        bodyView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        for option in ProofAnswer.allCases {
            let row = SelectableRowView(title: option.rawValue)
            row.isSelected = store.draft.proofAnswer == option
            row.addAction(UIAction { [weak self] _ in self?.select(option) }, for: .touchUpInside)
            rows.append((option, row))
            stack.addArrangedSubview(row)
        }

        bodyView.addSubview(hint)
        hint.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            hintBottomConstraint = make.bottom.equalToSuperview().inset(DesignSystem.Layout.Onboarding.questionHintBottom).constraint
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            hintTopConstraint = make.top.greaterThanOrEqualTo(stack.snp.bottom).offset(DesignSystem.Spacing.x18).constraint
        }
    }

    override func setCompactLayout(_ compact: Bool) {
        super.setCompactLayout(compact)
        stack.spacing = compact ? 10 : DesignSystem.Layout.Onboarding.rowSpacing
        hintBottomConstraint?.update(offset: compact ? -14 : -DesignSystem.Layout.Onboarding.questionHintBottom)
        hintTopConstraint?.update(offset: compact ? 12 : DesignSystem.Spacing.x18)
    }

    private func select(_ option: ProofAnswer) {
        let shouldClear = store.draft.proofAnswer == option
        store.update { $0.proofAnswer = shouldClear ? nil : option }
        for (item, row) in rows { row.isSelected = !shouldClear && item == option }
        onContinueAvailabilityChanged?(isContinueAllowed)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
