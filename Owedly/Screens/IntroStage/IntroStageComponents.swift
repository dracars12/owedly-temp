import UIKit
import SnapKit

extension UILabel {
    func applyAppText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        lineHeight: CGFloat? = nil,
        alignment: NSTextAlignment = .natural
    ) {
        self.numberOfLines = 0
        self.textAlignment = alignment
        self.font = font
        self.textColor = color
        guard let lineHeight else {
            self.text = text
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignment
        attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

final class LargeSuccessGlyphView: UIView {
    private let imageView = UIImageView()

    /// Figma uses a 115pt symbol text frame with the ~96pt checkmark centered inside it.
    /// Keeping the visual glyph and its layout frame separate preserves the exact vertical rhythm.
    init(size: CGFloat = 96, layoutSize: CGFloat = 115) {
        super.init(frame: .zero)
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        imageView.image = UIImage(systemName: "checkmark.circle", withConfiguration: config)
        imageView.tintColor = DesignSystem.Color.brandGreen
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(size)
        }
        snp.makeConstraints { $0.size.equalTo(layoutSize) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class MaterialSurfaceView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
    private let tintView = UIView()

    init(
        cornerRadius: CGFloat = DesignSystem.Radius.card,
        borderColor: UIColor = DesignSystem.Color.cardBorder,
        tintColor: UIColor = DesignSystem.Color.cardFill
    ) {
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor

        tintView.backgroundColor = tintColor
        addSubview(blurView)
        addSubview(tintView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }
        tintView.snp.makeConstraints { $0.edges.equalToSuperview() }
        sendSubviewToBack(blurView)
        tintView.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class ProcessStatusRow: UIView {
    enum State { case loading, complete }

    private let iconContainer = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let checkView = UIImageView()
    private let titleLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .appRegularFont(size: 16)
        titleLabel.textColor = DesignSystem.Color.textPrimary

        spinner.color = DesignSystem.Color.textSecondary
        spinner.hidesWhenStopped = true

        checkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkView.tintColor = DesignSystem.Color.brandGreen
        checkView.contentMode = .scaleAspectFit
        checkView.alpha = 0

        addSubview(iconContainer)
        addSubview(titleLabel)
        iconContainer.addSubview(spinner)
        iconContainer.addSubview(checkView)

        snp.makeConstraints { $0.height.equalTo(56) }
        iconContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        spinner.snp.makeConstraints { $0.edges.equalToSuperview() }
        checkView.snp.makeConstraints { $0.edges.equalToSuperview() }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconContainer.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        setState(.loading, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setState(_ state: State, animated: Bool) {
        switch state {
        case .loading:
            checkView.alpha = 0
            spinner.alpha = 1
            spinner.startAnimating()
        case .complete:
            let updates = {
                self.spinner.alpha = 0
                self.checkView.alpha = 1
                self.checkView.transform = .identity
            }
            spinner.stopAnimating()
            if animated {
                checkView.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
                UIView.animate(
                    withDuration: 0.34,
                    delay: 0,
                    usingSpringWithDamping: 0.66,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: updates
                )
            } else {
                updates()
            }
        }
    }
}

final class ScanProgressRow: UIView {
    private let track = UIView()
    private let fill = UIView()
    private let percentLabel = UILabel()
    private var fillWidthConstraint: Constraint?
    private var progress: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = DesignSystem.Color.progressTrack
        track.layer.cornerRadius = 3
        fill.backgroundColor = DesignSystem.Color.brandGreen
        fill.layer.cornerRadius = 3
        percentLabel.font = .appMediumFont(size: 16)
        percentLabel.textColor = DesignSystem.Color.textPrimary
        percentLabel.textAlignment = .right
        percentLabel.numberOfLines = 1
        percentLabel.adjustsFontSizeToFitWidth = true
        percentLabel.minimumScaleFactor = 0.70
        percentLabel.baselineAdjustment = .alignCenters
        percentLabel.lineBreakMode = .byClipping
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(track)
        track.addSubview(fill)
        addSubview(percentLabel)

        snp.makeConstraints { $0.height.equalTo(56) }
        track.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.centerY.equalToSuperview()
            make.height.equalTo(6)
        }
        percentLabel.snp.makeConstraints { make in
            make.leading.equalTo(track.snp.trailing).offset(16)
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
            make.width.equalTo(36)
        }
        fill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            fillWidthConstraint = make.width.equalTo(0).constraint
        }
        setProgress(0, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setProgress(_ value: CGFloat, animated: Bool) {
        progress = min(max(value, 0), 1)
        percentLabel.text = "\(Int((progress * 100).rounded()))%"
        layoutIfNeeded()
        let width = max(0, track.bounds.width * progress)
        fillWidthConstraint?.update(offset: width)
        guard animated else {
            UIView.performWithoutAnimation { self.layoutIfNeeded() }
            return
        }
        UIView.animate(withDuration: 0.38, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillWidthConstraint?.update(offset: track.bounds.width * progress)
    }
}

final class ProcessCardView: MaterialSurfaceView {
    private let stack = UIStackView()
    private var rows: [ProcessStatusRow] = []
    let progressRow = ScanProgressRow()

    override init(
        cornerRadius: CGFloat = DesignSystem.Radius.card,
        borderColor: UIColor = DesignSystem.Color.cardBorder,
        tintColor: UIColor = DesignSystem.Color.cardFill
    ) {
        super.init(cornerRadius: cornerRadius, borderColor: borderColor, tintColor: tintColor)
        stack.axis = .vertical
        stack.spacing = 0
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func appendRow(title: String, animated: Bool) -> ProcessStatusRow {
        let row = ProcessStatusRow(title: title)
        // Every status row is separated from the item below it. When the progress row
        // already exists, new stages are inserted directly above it so the progress
        // bar always remains the bottom row while stages reveal one by one.
        row.addBottomHairline()
        rows.append(row)

        if progressRow.superview != nil,
           let progressIndex = stack.arrangedSubviews.firstIndex(where: { $0 === progressRow }) {
            stack.insertArrangedSubview(row, at: progressIndex)
        } else {
            stack.addArrangedSubview(row)
        }

        if animated {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.985, y: 0.985)
            UIView.animate(
                withDuration: 0.40,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.22,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                row.alpha = 1
                row.transform = .identity
                self.superview?.layoutIfNeeded()
            }
        }
        return row
    }

    func addProgressRowIfNeeded(animated: Bool) {
        guard progressRow.superview == nil else { return }
        stack.addArrangedSubview(progressRow)
        if animated {
            progressRow.alpha = 0
            progressRow.transform = CGAffineTransform(translationX: 0, y: 6)
            UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.progressRow.alpha = 1
                self.progressRow.transform = .identity
                self.superview?.layoutIfNeeded()
            }
        }
    }
}

private extension UIView {
    func addBottomHairline() {
        let line = UIView()
        line.backgroundColor = DesignSystem.Color.cardBorder
        addSubview(line)
        line.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }
    }
}

final class ShimmerPrimaryButton: PrimaryButton {
    private let shimmerLayer = CAGradientLayer()
    private var shimmerTimer: Timer?
    private let breathingAnimationKey = "owedly.purchaseButton.breathing"

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        shimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.white.withAlphaComponent(0.70).cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerLayer.locations = [0, 0.34, 0.5, 0.66, 1]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(shimmerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerLayer.frame = bounds.offsetBy(dx: -bounds.width * 1.5, dy: 0)
        shimmerLayer.frame.size.width = bounds.width * 1.4
    }

    func startShimmering() {
        stopShimmering()
        startBreathing()

        // The CTA breathes continuously. The light sweep is deliberately much rarer:
        // exactly once every five seconds so the two effects do not feel tied together.
        shimmerTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performShimmer()
        }
    }

    func stopShimmering() {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
        shimmerLayer.removeAllAnimations()
        layer.removeAnimation(forKey: breathingAnimationKey)
        transform = .identity
    }

    private func startBreathing() {
        guard layer.animation(forKey: breathingAnimationKey) == nil else { return }

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.985
        animation.toValue = 1.018
        animation.duration = 1.65
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: breathingAnimationKey)
    }

    private func performShimmer() {
        guard window != nil, bounds.width > 0 else { return }
        let travel = bounds.width * 2.8
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = travel
        animation.duration = 0.9
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(animation, forKey: "owedly.shimmer")
    }
}

final class SubscriptionPlanCard: UIControl {
    let plan: PurchasePlan
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let detailLabel = UILabel()
    private let badge = UILabel()
    private let selectionImage = UIImageView()

    override var isSelected: Bool {
        didSet { applySelection(animated: window != nil && isSelected) }
    }

    init(plan: PurchasePlan) {
        self.plan = plan
        super.init(frame: .zero)
        layer.cornerRadius = 16
        layer.borderWidth = 1

        titleLabel.font = .appSemiBoldFont(size: 20)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82
        priceLabel.textColor = DesignSystem.Color.textPrimary
        priceLabel.numberOfLines = 1
        priceLabel.adjustsFontSizeToFitWidth = true
        priceLabel.minimumScaleFactor = 0.9
        // The custom app font has taller ascenders/descenders than UILabel's compact intrinsic
        // height can sometimes report. The weekly card gets an explicit line-height budget below
        // so strings such as "$7.99 / week" cannot crop at the top/bottom.
        detailLabel.font = .appMediumFont(size: 16)
        detailLabel.textColor = DesignSystem.Color.textSecondary
        badge.font = .appMediumFont(size: 14)
        badge.textColor = .white
        badge.backgroundColor = DesignSystem.Color.brandGreen
        badge.layer.cornerRadius = 6
        badge.clipsToBounds = true
        badge.textAlignment = .center
        selectionImage.contentMode = .scaleAspectFit

        addSubview(titleLabel)
        addSubview(priceLabel)
        addSubview(detailLabel)
        addSubview(badge)
        addSubview(selectionImage)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(selectionImage.snp.leading).offset(-8)
            if plan == .weekly {
                make.height.greaterThanOrEqualTo(24)
            }
        }
        selectionImage.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.trailing.equalToSuperview().inset(14)
            make.size.equalTo(24)
        }
        priceLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(5)
            make.trailing.lessThanOrEqualToSuperview().inset(48)
            if plan == .weekly {
                make.height.greaterThanOrEqualTo(28)
            }
        }
        badge.snp.makeConstraints { make in
            make.leading.equalTo(priceLabel.snp.trailing).offset(12)
            make.centerY.equalTo(priceLabel)
            make.height.equalTo(21)
            make.width.equalTo(78)
        }
        detailLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(priceLabel.snp.bottom).offset(7)
            make.bottom.lessThanOrEqualToSuperview().inset(14)
        }

        // The weekly card gets a small extra vertical budget because the custom title font can
        // otherwise clip on compact devices when the plan title is short (for example "Premium").
        // This keeps both the title and price fully visible without materially changing the paywall.
        snp.makeConstraints { $0.height.equalTo(plan == .annual ? 106 : 84) }
        setLoading()
        applySelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLoading() {
        isEnabled = false
        titleLabel.text = plan == .annual ? "Annual Access" : "Weekly Access"
        priceLabel.attributedText = Self.priceText(price: "Loading…", period: "")
        detailLabel.text = plan == .annual ? "Loading current App Store price" : nil
        badge.text = "Best value"
        badge.isHidden = plan != .annual
        alpha = 0.72
    }

    func configure(with product: PurchaseProductInfo) {
        isEnabled = true
        let trimmedTitle = product.localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = trimmedTitle.isEmpty
            ? (plan == .annual ? "Annual Access" : "Weekly Access")
            : trimmedTitle
        priceLabel.attributedText = Self.priceText(
            price: product.localizedPrice,
            period: "/ \(plan.displayPeriod)"
        )
        if plan == .annual, let weeklyEquivalent = product.weeklyEquivalentPrice {
            detailLabel.text = "Only \(weeklyEquivalent) per week"
        } else {
            detailLabel.text = nil
        }
        badge.text = "Best value"
        badge.isHidden = plan != .annual
        alpha = 1
    }

    func setUnavailable() {
        isEnabled = false
        titleLabel.text = plan == .annual ? "Annual Access" : "Weekly Access"
        priceLabel.attributedText = Self.priceText(price: "Unavailable", period: "")
        detailLabel.text = plan == .annual ? "Please try again" : nil
        badge.isHidden = true
        alpha = 0.62
    }

    private static func priceText(price: String, period: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: price,
            attributes: [.font: UIFont.appSemiBoldFont(size: 18), .foregroundColor: DesignSystem.Color.textPrimary]
        )
        if !period.isEmpty {
            result.append(NSAttributedString(
                string: " \(period)",
                attributes: [.font: UIFont.appMediumFont(size: 14), .foregroundColor: DesignSystem.Color.textPrimary]
            ))
        }
        return result
    }

    private func applySelection(animated: Bool) {
        let update = {
            self.backgroundColor = self.isSelected ? DesignSystem.Color.selectedCardFill : DesignSystem.Color.cardFill
            self.layer.borderColor = (self.isSelected ? DesignSystem.Color.brandGreen : DesignSystem.Color.cardBorder).cgColor
            self.selectionImage.image = UIImage(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
            self.selectionImage.tintColor = self.isSelected ? DesignSystem.Color.brandGreen : DesignSystem.Color.textTertiary
        }
        guard animated else { update(); return }
        transform = CGAffineTransform(scaleX: 0.982, y: 0.982)
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.4, options: [.curveEaseOut, .allowUserInteraction]) {
            update()
            self.transform = .identity
        }
    }
}

final class FauxNotificationView: UIView {
    init() {
        super.init(frame: .zero)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
        let icon = UIImageView(image: UIImage(named: "notification_app_icon"))
        icon.layer.cornerRadius = 8.5
        icon.clipsToBounds = true
        let title = UILabel()
        title.text = "New Settlement Match"
        title.font = .appSemiBoldFont(size: 15)
        title.textColor = .black
        let time = UILabel()
        time.text = "Now"
        time.font = .appRegularFont(size: 13)
        // Figma's vibrant secondary label reads lighter than the regular body text
        // on the translucent notification material.
        time.textColor = UIColor(hex: 0x7F7F7F)
        time.textAlignment = .right
        let body = UILabel()
        body.text = "A new settlement may match your profile"
        body.font = .appRegularFont(size: 15)
        body.textColor = .black

        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 5)
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        blur.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.62)

        addSubview(blur)
        blur.contentView.addSubview(icon)
        blur.contentView.addSubview(title)
        blur.contentView.addSubview(time)
        blur.contentView.addSubview(body)

        blur.snp.makeConstraints { $0.edges.equalToSuperview() }
        snp.makeConstraints { $0.height.equalTo(66) }
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(38)
        }
        title.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(10)
            make.top.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualTo(time.snp.leading).offset(-8)
        }
        time.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(14)
            make.top.equalTo(title.snp.top).offset(-1)
            make.width.equalTo(40)
        }
        body.snp.makeConstraints { make in
            make.leading.equalTo(title)
            make.top.equalTo(title.snp.bottom).offset(1)
            make.trailing.equalToSuperview().inset(12)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
