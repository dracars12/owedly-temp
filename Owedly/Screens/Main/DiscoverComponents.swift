import UIKit
import SnapKit
import SafariServices

final class SettlementImageLoader {
    static let shared = SettlementImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let representedURLs = NSMapTable<UIImageView, NSURL>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private let diskQueue = DispatchQueue(label: "app.owedly.settlement-image-cache", qos: .utility)
    private let diskDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskDirectory = caches.appendingPathComponent("SettlementImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        cache.countLimit = 240
    }

    /// Returns immediately when the image is already cached. We check the in-memory cache first,
    /// then the small on-disk cache synchronously so a cell that is being rebuilt while returning
    /// from another screen can render the real artwork on its very first frame instead of flashing
    /// the compact shield placeholder and growing a moment later.
    func cachedImage(for url: URL) -> UIImage? {
        if let memoryImage = cache.object(forKey: url as NSURL) {
            return memoryImage
        }

        let fileURL = diskURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Loads an image without binding the request to a reusable view. The cache has two levels:
    /// NSCache for instant reuse during the current session, plus a small disk cache for later runs.
    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cachedImage(for: url) {
            if Thread.isMainThread { completion(cached) }
            else { DispatchQueue.main.async { completion(cached) } }
            return
        }

        let diskURL = diskURL(for: url)
        diskQueue.async { [weak self] in
            guard let self else { return }
            if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
                self.cache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async { completion(image) }
                return
            }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self else { return }
                let image = data.flatMap(UIImage.init(data:))
                if let image, let data {
                    self.cache.setObject(image, forKey: url as NSURL)
                    self.diskQueue.async {
                        try? data.write(to: diskURL, options: .atomic)
                    }
                }
                DispatchQueue.main.async { completion(image) }
            }.resume()
        }
    }

    func applyPlaceholder(to imageView: UIImageView, tint: UIColor) {
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        imageView.contentMode = .center
        imageView.image = UIImage(systemName: "checkmark.shield")
        imageView.tintColor = tint
    }

    func applyImage(_ image: UIImage, to imageView: UIImageView) {
        imageView.preferredSymbolConfiguration = nil
        imageView.contentMode = .scaleAspectFill
        imageView.image = image
        imageView.tintColor = nil
    }

    /// Convenience API for non-reusable views such as detail headers and promo cards.
    func load(
        _ url: URL?,
        into imageView: UIImageView,
        placeholder: UIImage? = UIImage(systemName: "checkmark.shield"),
        placeholderTint: UIColor = DesignSystem.Color.brandGreen
    ) {
        if let url, let cached = cachedImage(for: url) {
            representedURLs.setObject(url as NSURL, forKey: imageView)
            applyImage(cached, to: imageView)
            return
        }

        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        imageView.contentMode = .center
        imageView.image = placeholder
        imageView.tintColor = placeholderTint

        guard let url else {
            representedURLs.removeObject(forKey: imageView)
            return
        }
        representedURLs.setObject(url as NSURL, forKey: imageView)
        image(for: url) { [weak self, weak imageView] image in
            guard let self, let imageView, let image else { return }
            guard self.representedURLs.object(forKey: imageView) == url as NSURL else { return }
            self.applyImage(image, to: imageView)
        }
    }

    private func diskURL(for url: URL) -> URL {
        // Deterministic FNV-1a key avoids importing a hashing framework just for cache filenames.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return diskDirectory.appendingPathComponent(String(hash, radix: 16) + ".img")
    }
}

final class SettlementOfferCell: UITableViewCell {
    static let reuseID = "SettlementOfferCell"

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
        statusLabel.numberOfLines = 1
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.80
        dateLabel.font = .appMediumFont(size: 14)
        dateLabel.textColor = DesignSystem.Color.textSecondary
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
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-10)
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
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        representedImageURL = nil
        // Do not force the tiny placeholder here. `configure` immediately decides whether the
        // next settlement has cached artwork. Keeping the previous bitmap until that decision is
        // made avoids a one-frame "small shield -> full logo" flash during table reloads.
    }

    func animateIn(delay: TimeInterval) {
        layer.removeAllAnimations()
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.985, y: 0.985)
        UIView.animate(
            withDuration: DesignSystem.Animation.screenDuration,
            delay: delay,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.12,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func configure(with settlement: Settlement) {
        titleLabel.text = settlement.title
        switch settlement.status {
        case .upcoming:
            dot.backgroundColor = DesignSystem.Color.iconBlue
            statusLabel.textColor = DesignSystem.Color.iconBlue
            statusLabel.text = "Upcoming"
            dateLabel.text = settlement.deadline.map { "Starts \(Self.dateFormatter.string(from: $0))" } ?? "Coming soon"
        default:
            dot.backgroundColor = DesignSystem.Color.brandGreen
            statusLabel.textColor = DesignSystem.Color.brandGreen
            let payout = settlement.payoutText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            statusLabel.text = payout.isEmpty ? "Varies" : payout
            dateLabel.text = settlement.deadline.map { "Deadline \(Self.dateFormatter.string(from: $0))" } ?? "Deadline not listed"
        }
        let placeholderTint = settlement.status == .upcoming ? DesignSystem.Color.iconBlue : DesignSystem.Color.brandGreen
        representedImageURL = settlement.imageURL

        guard let imageURL = settlement.imageURL else {
            SettlementImageLoader.shared.applyPlaceholder(to: iconView, tint: placeholderTint)
            return
        }
        if let cached = SettlementImageLoader.shared.cachedImage(for: imageURL) {
            SettlementImageLoader.shared.applyImage(cached, to: iconView)
            return
        }

        SettlementImageLoader.shared.applyPlaceholder(to: iconView, tint: placeholderTint)
        SettlementImageLoader.shared.image(for: imageURL) { [weak self] image in
            guard let self, self.representedImageURL == imageURL, let image else { return }
            SettlementImageLoader.shared.applyImage(image, to: self.iconView)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

final class CategoryPillCell: UICollectionViewCell {
    static let reuseID = "CategoryPillCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 17.5
        contentView.layer.borderWidth = 1
        label.font = .appMediumFont(size: 14)
        label.textAlignment = .center
        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, selected: Bool) {
        label.text = title
        if selected {
            contentView.backgroundColor = DesignSystem.Color.brandGreen.withAlphaComponent(0.06)
            contentView.layer.borderColor = DesignSystem.Color.brandGreen.cgColor
            label.textColor = DesignSystem.Color.brandGreen
        } else {
            contentView.backgroundColor = .white
            contentView.layer.borderColor = UIColor.black.withAlphaComponent(0.20).cgColor
            label.textColor = UIColor.black.withAlphaComponent(0.60)
        }
    }
}

extension UIViewController {
    /// Resolves a newly-created controller's first constraint pass before UIKit starts the push.
    /// This avoids iOS 26 visibly interpolating a fresh layout tree from the corner.
    func pushPreparedViewController(_ controller: UIViewController, animated: Bool = true) {
        guard let navigationController else { return }
        controller.loadViewIfNeeded()
        controller.view.frame = navigationController.view.bounds
        UIView.performWithoutAnimation {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        navigationController.pushViewController(controller, animated: animated)
    }

    func showSettlementDetails(_ settlement: Settlement) {
        navigationItem.backButtonDisplayMode = .minimal
        let details = SettlementDetailsViewController(settlement: settlement)

        // Fully resolve the first Auto Layout pass before the navigation transition starts.
        // Without this, iOS 26 can visibly interpolate a just-created constraint tree during
        // the push, which looks like the detail screen is being constructed from a corner.
        details.loadViewIfNeeded()
        if let navigationController {
            details.view.frame = navigationController.view.bounds
            UIView.performWithoutAnimation {
                details.view.setNeedsLayout()
                details.view.layoutIfNeeded()
            }
            navigationController.pushViewController(details, animated: true)
        } else {
            details.view.frame = view.bounds
            UIView.performWithoutAnimation {
                details.view.setNeedsLayout()
                details.view.layoutIfNeeded()
            }
            let navigation = UINavigationController(rootViewController: details)
            navigation.overrideUserInterfaceStyle = .light
            present(navigation, animated: true)
        }
    }

    func openSettlementSource(_ settlement: Settlement) {
        guard let url = settlement.sourceURL ?? settlement.officialClaimURL else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = DesignSystem.Color.brandGreen
        present(safari, animated: true)
    }
}

/// Top-edge fade adapted directly from the project owner's FadeTableView.
/// Only the upper edge is masked; there is intentionally no bottom fade.
final class FadeTableView: UITableView, CAAnimationDelegate {
    let fadePoints: CGFloat = 32
    let gradientLayer = CAGradientLayer()
    let opaqueColor = UIColor.black.cgColor
    var isFadeEnabled = true
    var topFadeThreshold: CGFloat = 10

    private var topFadingOpacity: CGColor {
        let effectiveOffset = contentOffset.y + adjustedContentInset.top
        let alpha: CGFloat = effectiveOffset <= topFadeThreshold ? 1 : 0
        return UIColor(white: 0, alpha: alpha).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFadeMask()
    }

    private func applyFadeMask() {
        guard isFadeEnabled, bounds.height > 0 else {
            layer.mask = nil
            return
        }

        // Preserve the geometry used by the original FadeTableView. In particular, the
        // gradient's vertical origin is kept at zero while the table's bounds origin changes,
        // which keeps the visible fade pinned to the table's top edge instead of the rows.
        let maskLayer = CALayer()
        maskLayer.frame = bounds

        let gradientLocation = min(max(fadePoints / bounds.height, 0), 1)
        gradientLayer.frame = CGRect(
            x: bounds.origin.x,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.colors = [topFadingOpacity, opaqueColor]
        gradientLayer.locations = [0, NSNumber(value: Double(gradientLocation))]

        maskLayer.addSublayer(gradientLayer)
        layer.mask = maskLayer
    }

    /// Update gradient depending on the current content offset.
    /// Call from scrollViewDidScroll.
    func updateGradient() {
        guard isFadeEnabled else {
            layer.mask = nil
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = [topFadingOpacity, opaqueColor]
        CATransaction.commit()
    }
}

final class EmptySectionPlaceholderView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        titleLabel.font = .appSemiBoldFont(size: 16)
        titleLabel.textColor = DesignSystem.Color.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        subtitleLabel.font = .appMediumFont(size: 14)
        subtitleLabel.textColor = DesignSystem.Color.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(7)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
}
