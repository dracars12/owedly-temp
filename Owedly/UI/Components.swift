import UIKit
import SnapKit

// MARK: - Background

/// Reproduces the two-layer Figma background: a cream -> mint linear gradient
/// plus the soft blue radial glow sitting just outside the top-right edge.
final class SoftBackgroundView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        backgroundColor = DesignSystem.Color.gradientMint
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        if let base = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                DesignSystem.Color.gradientCream.cgColor,
                DesignSystem.Color.gradientMint.cgColor
            ] as CFArray,
            locations: [0, 1]
        ) {
            // Normalized from the exact 393 x 852 Figma gradient transform.
            let start = CGPoint(x: -2.16794 * bounds.width, y: 0.46127 * bounds.height)
            let end = CGPoint(x: -1.16794 * bounds.width, y: 1.46127 * bounds.height)
            context.drawLinearGradient(
                base,
                start: start,
                end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        if let glow = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                DesignSystem.Color.gradientBlue.cgColor,
                DesignSystem.Color.gradientBlue.withAlphaComponent(0).cgColor
            ] as CFArray,
            locations: [0, 1]
        ) {
            let center = CGPoint(x: 1.04198 * bounds.width, y: 0.08157 * bounds.height)
            let radius = 1.43766 * bounds.width
            context.drawRadialGradient(
                glow,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsBeforeStartLocation]
            )
        }
    }
}

// MARK: - Brand

final class OwedlyLogoView: UIImageView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        image = UIImage(named: "owedly_logo_group")
        contentMode = .scaleAspectFit
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        image = UIImage(named: "owedly_logo_group")
        contentMode = .scaleAspectFit
        clipsToBounds = false
    }

    override var intrinsicContentSize: CGSize {
        DesignSystem.Size.logo
    }
}

// MARK: - Buttons / progress

class PrimaryButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignSystem.Color.brandGreen
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .appSemiBoldFont(size: 20)
        layer.cornerRadius = DesignSystem.Radius.button
        clipsToBounds = true
        adjustsImageWhenHighlighted = false
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        snp.makeConstraints { $0.height.equalTo(DesignSystem.Size.primaryButtonHeight) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.10, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: 0.986, y: 0.986)
            self.alpha = 0.95
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}

final class ProgressBarView: UIView {
    private let fillView = UIView()
    private var progress: CGFloat = 0.0001

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignSystem.Color.progressTrack
        layer.cornerRadius = DesignSystem.Size.progressHeight / 2
        clipsToBounds = true

        fillView.backgroundColor = DesignSystem.Color.brandGreen
        fillView.layer.cornerRadius = DesignSystem.Size.progressHeight / 2
        addSubview(fillView)
        fillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(progress)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setProgress(_ newProgress: CGFloat, animated: Bool) {
        progress = max(0.0001, min(1, newProgress))
        fillView.snp.remakeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(progress)
        }

        if !animated || window == nil {
            UIView.performWithoutAnimation { self.layoutIfNeeded() }
            return
        }

        // The track never moves. Only the green fill width changes.
        UIView.animate(
            withDuration: DesignSystem.Animation.progressDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.layoutIfNeeded()
        }
    }
}

// MARK: - Selectable cards

enum RowSelectionAppearance {
    /// Selection is represented by the green border/check only.
    case outline
    /// Selection also receives the subtle 10% green surface from Figma.
    case tinted
}

final class SelectableRowView: UIControl {
    let titleLabel = UILabel()
    private let checkImageView = UIImageView()
    private let selectionAppearance: RowSelectionAppearance

    override var isSelected: Bool {
        didSet { applySelection(animated: window != nil && isSelected) }
    }

    init(
        title: String,
        height: CGFloat = DesignSystem.Size.rowHeight,
        selectionAppearance: RowSelectionAppearance = .outline
    ) {
        self.selectionAppearance = selectionAppearance
        super.init(frame: .zero)

        backgroundColor = DesignSystem.Color.cardFill
        layer.cornerRadius = DesignSystem.Radius.card
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.cardBorder.cgColor

        titleLabel.text = title
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.font = .appSemiBoldFont(size: 18)

        checkImageView.contentMode = .scaleAspectFit

        addSubview(titleLabel)
        addSubview(checkImageView)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(DesignSystem.Spacing.x17)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(checkImageView.snp.leading).offset(-DesignSystem.Spacing.x10)
        }
        checkImageView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(DesignSystem.Spacing.x13)
            make.centerY.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.selectionIcon)
        }
        snp.makeConstraints { $0.height.equalTo(height) }
        applySelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applySelection(animated: Bool) {
        let updates = {
            if self.isSelected, self.selectionAppearance == .tinted {
                self.backgroundColor = DesignSystem.Color.selectedCardFill
            } else {
                self.backgroundColor = DesignSystem.Color.cardFill
            }

            self.layer.borderColor = self.isSelected
                ? DesignSystem.Color.brandGreen.cgColor
                : DesignSystem.Color.cardBorder.cgColor

            self.checkImageView.image = UIImage(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
            self.checkImageView.tintColor = self.isSelected
                ? DesignSystem.Color.brandGreen
                : DesignSystem.Color.textTertiary
        }

        guard animated else {
            updates()
            return
        }

        transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        UIView.animate(
            withDuration: DesignSystem.Animation.selectionDuration,
            delay: 0,
            usingSpringWithDamping: 0.74,
            initialSpringVelocity: 0.32,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            updates()
            self.transform = .identity
        }
    }
}

final class CompanyCardView: UIControl {
    let option: CompanyOption
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let checkImageView = UIImageView()

    override var isSelected: Bool {
        didSet { applySelection(animated: window != nil && isSelected) }
    }

    init(option: CompanyOption) {
        self.option = option
        super.init(frame: .zero)

        backgroundColor = DesignSystem.Color.cardFill
        layer.cornerRadius = DesignSystem.Radius.card
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.cardBorder.cgColor

        iconView.image = UIImage(named: option.imageName)
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = option.rawValue
        titleLabel.textAlignment = .center
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.font = .appSemiBoldFont(size: 18)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.numberOfLines = 1

        checkImageView.contentMode = .scaleAspectFit

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(checkImageView)

        // Figma cards are 174x109: 48pt logo at y=17, a 6pt gap to the
        // title, and a 24pt selection glyph at x=140/y=10.
        checkImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(DesignSystem.Spacing.x10)
            make.trailing.equalToSuperview().inset(DesignSystem.Spacing.x10)
            make.size.equalTo(DesignSystem.Size.selectionIcon)
        }
        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(DesignSystem.Spacing.x17)
            make.centerX.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.companyIcon)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Spacing.x6)
            make.top.equalTo(iconView.snp.bottom).offset(DesignSystem.Spacing.x6)
            make.height.greaterThanOrEqualTo(21)
        }
        snp.makeConstraints { $0.height.equalTo(DesignSystem.Size.companyCardHeight) }
        applySelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applySelection(animated: Bool) {
        let updates = {
            self.backgroundColor = self.isSelected
                ? DesignSystem.Color.selectedCardFill
                : DesignSystem.Color.cardFill
            self.layer.borderColor = self.isSelected
                ? DesignSystem.Color.brandGreen.cgColor
                : DesignSystem.Color.cardBorder.cgColor
            self.checkImageView.image = UIImage(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
            self.checkImageView.tintColor = self.isSelected
                ? DesignSystem.Color.brandGreen
                : DesignSystem.Color.textTertiary
        }

        guard animated else { updates(); return }

        transform = CGAffineTransform(scaleX: 0.976, y: 0.976)
        UIView.animate(
            withDuration: DesignSystem.Animation.selectionDuration,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.38,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            updates()
            self.transform = .identity
        }
    }
}

// MARK: - Supporting UI

final class HintView: UIView {
    init(symbolName: String, text: String, tint: UIColor) {
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.textColor = DesignSystem.Color.textSecondary
        label.font = .appMediumFont(size: 16)
        label.numberOfLines = 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = DesignSystem.Layout.LineHeight.body16
        paragraph.maximumLineHeight = DesignSystem.Layout.LineHeight.body16
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.appMediumFont(size: 16),
                .foregroundColor: DesignSystem.Color.textSecondary,
                .paragraphStyle: paragraph
            ]
        )

        addSubview(icon)
        addSubview(label)

        icon.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.helperIcon)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(DesignSystem.Spacing.x8)
            make.trailing.top.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class MatchPreviewCard: UIView {
    init(deadlineText: String) {
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.cardFill
        layer.cornerRadius = DesignSystem.Radius.card
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Color.cardBorder.cgColor

        let logoContainer = UIView()
        logoContainer.backgroundColor = .white
        logoContainer.layer.cornerRadius = DesignSystem.Radius.introGoogleBadge
        logoContainer.layer.borderWidth = 1
        logoContainer.layer.borderColor = DesignSystem.Color.cardBorder.cgColor
        logoContainer.clipsToBounds = true

        let logo = UIImageView(image: UIImage(named: "company_google_group"))
        logo.contentMode = .scaleAspectFit

        let company = UILabel()
        company.text = "Google"
        company.textColor = DesignSystem.Color.textPrimary
        company.font = .appBoldFont(size: 16)

        let statusDot = UIView()
        statusDot.backgroundColor = DesignSystem.Color.brandGreen
        statusDot.layer.cornerRadius = 4

        let status = UILabel()
        status.text = "Match available"
        status.textColor = DesignSystem.Color.brandGreen
        status.font = .appMediumFont(size: 14)

        let deadline = UILabel()
        deadline.text = deadlineText
        deadline.textColor = DesignSystem.Color.textSecondary
        deadline.font = .appMediumFont(size: 14)

        let searchImage = UIImage(systemName: "sparkle.magnifyingglass")
            ?? UIImage(systemName: "magnifyingglass")
        let searchIcon = UIImageView(image: searchImage)
        searchIcon.tintColor = DesignSystem.Color.brandGreen
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)

        addSubview(logoContainer)
        logoContainer.addSubview(logo)
        addSubview(company)
        addSubview(statusDot)
        addSubview(status)
        addSubview(deadline)
        addSubview(searchIcon)

        // Figma 77:1986 / 77:1987: 16pt card padding, 44pt Google badge,
        // 12pt badge-to-copy gap, then 8pt/6pt vertical copy gaps.
        logoContainer.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(DesignSystem.Spacing.x17)
            make.size.equalTo(DesignSystem.Size.introGoogleBadge)
        }
        logo.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.introGoogleMark)
        }
        company.snp.makeConstraints { make in
            make.leading.equalTo(logoContainer.snp.trailing).offset(DesignSystem.Spacing.x12)
            make.top.equalToSuperview().offset(DesignSystem.Spacing.x17)
        }
        status.snp.makeConstraints { make in
            make.leading.equalTo(company)
            make.top.equalTo(company.snp.bottom).offset(DesignSystem.Spacing.x8)
        }
        statusDot.snp.makeConstraints { make in
            make.leading.equalTo(company)
            make.centerY.equalTo(status)
            make.size.equalTo(DesignSystem.Size.statusDot)
        }
        status.snp.remakeConstraints { make in
            make.leading.equalTo(statusDot.snp.trailing).offset(DesignSystem.Spacing.x6)
            make.top.equalTo(company.snp.bottom).offset(DesignSystem.Spacing.x8)
        }
        deadline.snp.makeConstraints { make in
            make.leading.equalTo(company)
            make.top.equalTo(status.snp.bottom).offset(DesignSystem.Spacing.x6)
        }
        searchIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(DesignSystem.Spacing.x17)
            make.centerY.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.introSearchIcon)
        }
        snp.makeConstraints { $0.height.equalTo(DesignSystem.Size.introMatchCardHeight) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// UIScrollView whose content softly disappears at the visible edges instead of
/// ending on a hard clipping line. The mask is enabled only on an edge where
/// more content actually exists, so the first/last row remains fully opaque
/// when the user reaches the corresponding end.
final class EdgeFadingScrollView: UIScrollView {
    var fadeLength: CGFloat = 24
    var fadesTopEdge = true
    var fadesBottomEdge = true
    var topFadeThreshold: CGFloat = 8
    var bottomFadeThreshold: CGFloat = 8

    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureFadeMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFadeMask()
    }

    private func configureFadeMask() {
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = fadeMask
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFadeMask()
    }

    func updateFadeMask() {
        guard bounds.height > 1 else { return }

        let topEdge = -adjustedContentInset.top
        let bottomEdge = max(
            topEdge,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        let canScroll = bottomEdge > topEdge + 1
        let fadesTop = fadesTopEdge && canScroll && contentOffset.y > topEdge + topFadeThreshold
        let fadesBottom = fadesBottomEdge && canScroll && contentOffset.y < bottomEdge - bottomFadeThreshold
        let fraction = min(0.18, fadeLength / bounds.height)

        let clear = UIColor.clear.cgColor
        let opaque = UIColor.black.cgColor

        switch (fadesTop, fadesBottom) {
        case (true, true):
            fadeMask.colors = [clear, opaque, opaque, clear]
        case (true, false):
            fadeMask.colors = [clear, opaque, opaque, opaque]
        case (false, true):
            fadeMask.colors = [opaque, opaque, opaque, clear]
        case (false, false):
            fadeMask.colors = [opaque, opaque, opaque, opaque]
        }
        fadeMask.locations = [
            NSNumber(value: 0),
            NSNumber(value: Double(fraction)),
            NSNumber(value: Double(1 - fraction)),
            NSNumber(value: 1)
        ]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Match the viewport instead of an individual content row. UIScrollView changes
        // bounds.origin while scrolling, so the mask follows the visible rect itself.
        fadeMask.frame = bounds
        CATransaction.commit()
    }
}

/// Horizontal companion to `EdgeFadingScrollView`. It keeps the fade pinned to the viewport
/// and only reveals it on an edge that still has hidden content, so horizontally scrolling chips
/// feel soft instead of being clipped by a hard vertical line.
final class HorizontalEdgeFadingScrollView: UIScrollView {
    var fadeLength: CGFloat = 18
    var leftFadeThreshold: CGFloat = 4
    var rightFadeThreshold: CGFloat = 4

    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureFadeMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFadeMask()
    }

    private func configureFadeMask() {
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        layer.mask = fadeMask
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFadeMask()
    }

    func updateFadeMask() {
        guard bounds.width > 1 else { return }

        let leftEdge = -adjustedContentInset.left
        let rightEdge = max(
            leftEdge,
            contentSize.width - bounds.width + adjustedContentInset.right
        )
        let canScroll = rightEdge > leftEdge + 1
        let fadesLeft = canScroll && contentOffset.x > leftEdge + leftFadeThreshold
        let fadesRight = canScroll && contentOffset.x < rightEdge - rightFadeThreshold
        let fraction = min(0.22, fadeLength / bounds.width)

        let clear = UIColor.clear.cgColor
        let opaque = UIColor.black.cgColor

        switch (fadesLeft, fadesRight) {
        case (true, true):
            fadeMask.colors = [clear, opaque, opaque, clear]
        case (true, false):
            fadeMask.colors = [clear, opaque, opaque, opaque]
        case (false, true):
            fadeMask.colors = [opaque, opaque, opaque, clear]
        case (false, false):
            fadeMask.colors = [opaque, opaque, opaque, opaque]
        }
        fadeMask.locations = [
            NSNumber(value: 0),
            NSNumber(value: Double(fraction)),
            NSNumber(value: Double(1 - fraction)),
            NSNumber(value: 1)
        ]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        CATransaction.commit()
    }
}

final class SearchField: UIView, UITextFieldDelegate {
    let textField = UITextField()
    var textDidChange: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignSystem.Color.searchFill
        layer.cornerRadius = DesignSystem.Radius.search
        clipsToBounds = true

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = DesignSystem.Color.textPrimary
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        textField.font = .appRegularFont(size: 16)
        textField.textColor = DesignSystem.Color.textPrimary
        textField.tintColor = DesignSystem.Color.brandGreen
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search state",
            attributes: [
                .font: UIFont.appRegularFont(size: 16),
                .foregroundColor: DesignSystem.Color.textSecondary
            ]
        )
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .words
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        
        addSubview(icon)
        addSubview(textField)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(DesignSystem.Spacing.x16)
            make.centerY.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.searchIcon)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(DesignSystem.Spacing.x6)
            make.trailing.equalToSuperview().inset(DesignSystem.Spacing.x16)
            make.top.bottom.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(DesignSystem.Size.searchHeight) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func textChanged() {
        textDidChange?(textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }


}

// MARK: - Card entrance animation

/// Hidden/offset state is prepared before a pseudo-screen becomes visible, so
/// there is never a fully-rendered frame before the entrance animation begins.
func prepareCardEntrance(_ views: [UIView]) {
    for view in views where !view.isHidden {
        view.layer.removeAllAnimations()
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 14)
            .scaledBy(x: 0.965, y: 0.965)
    }
}

func animatePreparedCardEntrance(_ views: [UIView]) {
    let visible = views.filter { !$0.isHidden }
    for (index, view) in visible.enumerated() {
        UIView.animate(
            withDuration: DesignSystem.Animation.cardDuration,
            delay: Double(index) * DesignSystem.Animation.cardStagger,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.22,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            view.alpha = 1
            view.transform = .identity
        }
    }
}

func animateCardEntrance(_ views: [UIView]) {
    prepareCardEntrance(views)
    animatePreparedCardEntrance(views)
}
