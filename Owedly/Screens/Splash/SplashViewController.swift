import UIKit
import SnapKit

final class SplashViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let logoView = OwedlyLogoView(frame: .zero)

    override func loadView() {
        view = SoftBackgroundView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(logoView)
        logoView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(DesignSystem.Size.logo)
        }

        logoView.alpha = 0
        logoView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(
            withDuration: 0.38,
            delay: 0.04,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.logoView.alpha = 1
            self.logoView.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.onFinished?()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
