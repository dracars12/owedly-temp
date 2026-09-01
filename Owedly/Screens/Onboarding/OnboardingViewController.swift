import UIKit
import SnapKit

final class OnboardingViewController: UIViewController {
    var onBackToIntro: (() -> Void)?
    var onFinished: (() -> Void)?

    private let store: OnboardingStore
    private let backButton = UIButton(type: .system)
    private let stepLabel = UILabel()
    private let progressView = ProgressBarView()
    private let contentContainer = UIView()
    private let primaryButton = PrimaryButton(frame: .zero)

    private var currentIndex = 0
    private var isTransitioning = false
    private var hasAnimatedInitialContent = false
    private var hasResolvedInitialSafeAreaLayout = false
    private var appliedCompactLayout: Bool?

    // A touch slower than the rest of the app so onboarding pseudo-screen changes feel calmer.
    private let onboardingTransitionDuration = DesignSystem.Animation.screenDuration * 1.125

    private lazy var steps: [OnboardingStepView] = [
        StateSelectionStepView(store: store),
        CompaniesStepView(store: store),
        TimePeriodsStepView(store: store),
        CategoriesStepView(store: store),
        NoticesQuestionStepView(store: store),
        ProofQuestionStepView(store: store)
    ]

    init(store: OnboardingStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SoftBackgroundView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureChrome()
        configureStepContinueAvailability()
        showInitialStepWithoutAnimation()
        configureKeyboardDismissal()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayoutIfNeeded()

        // Wait until the controller is actually inside a window. Before this point the safe-area
        // can still be zero, so forcing layout would make the fixed onboarding chrome jump later.
        guard !hasResolvedInitialSafeAreaLayout, view.window != nil else { return }
        hasResolvedInitialSafeAreaLayout = true

        // Let the final safe-area layout be committed first. The following animation changes only
        // the pseudo-screen content; back/step/progress track/CTA remain in their final positions.
        DispatchQueue.main.async { [weak self] in
            self?.animateInitialContentIfNeeded()
        }
    }

    private func configureChrome() {
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = DesignSystem.Color.textSecondary
        backButton.contentHorizontalAlignment = .leading
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        stepLabel.font = .appMediumFont(size: 14)
        stepLabel.textColor = DesignSystem.Color.textSecondary
        stepLabel.textAlignment = .right

        primaryButton.setTitle("Continue", for: .normal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        contentContainer.clipsToBounds = false

        view.addSubview(backButton)
        view.addSubview(stepLabel)
        view.addSubview(progressView)
        view.addSubview(contentContainer)
        view.addSubview(primaryButton)

        applyChromeLayout(compact: false)

    }

    private func updateResponsiveLayoutIfNeeded() {
        guard view.bounds.height > 0 else { return }
        let compact = view.bounds.height <= 760
        guard appliedCompactLayout != compact else { return }
        applyChromeLayout(compact: compact)
        steps.forEach { $0.setCompactLayout(compact) }
        UIView.performWithoutAnimation {
            self.view.layoutIfNeeded()
        }
    }

    private func applyChromeLayout(compact: Bool) {
        appliedCompactLayout = compact

        backButton.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(DesignSystem.Layout.horizontalInset)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 0 : DesignSystem.Layout.Onboarding.navigationTop)
            make.size.equalTo(DesignSystem.Size.navigationRowHeight)
        }

        stepLabel.snp.remakeConstraints { make in
            make.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            make.centerY.equalTo(backButton)
        }

        progressView.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(compact ? 48 : DesignSystem.Layout.Onboarding.progressTopFromSafeArea)
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            make.height.equalTo(DesignSystem.Size.progressHeight)
        }

        primaryButton.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(compact ? 10 : DesignSystem.Layout.Onboarding.footerBottom)
            make.height.equalTo(DesignSystem.Size.primaryButtonHeight)
        }

        contentContainer.snp.remakeConstraints { make in
            make.top.equalTo(progressView.snp.bottom).offset(compact ? 14 : DesignSystem.Layout.Onboarding.contentTop)
            make.leading.trailing.equalToSuperview().inset(DesignSystem.Layout.horizontalInset)
            make.bottom.equalTo(primaryButton.snp.top).offset(compact ? -10 : -DesignSystem.Layout.Onboarding.footerTop)
        }
    }

    private func configureStepContinueAvailability() {
        for step in steps {
            step.onContinueAvailabilityChanged = { [weak self, weak step] isAvailable in
                guard let self, let step,
                      self.steps.indices.contains(self.currentIndex),
                      self.steps[self.currentIndex] === step else { return }
                self.setPrimaryButtonVisible(isAvailable, animated: true)
            }
        }
    }

    private func setPrimaryButtonVisible(_ isVisible: Bool, animated: Bool) {
        primaryButton.isUserInteractionEnabled = isVisible
        primaryButton.accessibilityElementsHidden = !isVisible

        let changes = {
            self.primaryButton.alpha = isVisible ? 1 : 0
            self.primaryButton.transform = isVisible
                ? .identity
                : CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.985, y: 0.985)
        }

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private func updatePrimaryButtonAvailability(for step: OnboardingStepView, animated: Bool) {
        let isVisible = !step.requiresExplicitAnswerBeforeContinue || step.isContinueAllowed
        setPrimaryButtonVisible(isVisible, animated: animated)
    }

    private func configureKeyboardDismissal() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func showInitialStepWithoutAnimation() {
        let step = steps[currentIndex]

        // Prepare every animation state before the controller is attached to the window.
        // This prevents the initial "render -> jump -> animate" frame completely.
        step.prepareForPresentation()
        step.alpha = 0
        step.transform = CGAffineTransform(translationX: 12, y: 0).scaledBy(x: 0.985, y: 0.985)

        contentContainer.addSubview(step)
        step.snp.makeConstraints { $0.edges.equalToSuperview() }

        stepLabel.text = "Step 1 of \(steps.count)"
        primaryButton.setTitle("Continue", for: .normal)
        progressView.setProgress(1.0 / CGFloat(steps.count), animated: false)
        updatePrimaryButtonAvailability(for: step, animated: false)

    }

    private func animateInitialContentIfNeeded() {
        guard !hasAnimatedInitialContent else { return }
        hasAnimatedInitialContent = true

        let step = steps[currentIndex]

        // Chrome is already fully laid out and visible at this point.
        // Only the pseudo-screen itself animates in.
        UIView.animate(
            withDuration: DesignSystem.Animation.screenDuration,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.12,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            step.alpha = 1
            step.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak step] in
            step?.animateCards()
        }
    }

    @objc private func primaryTapped() {
        guard !isTransitioning else { return }
        let currentStep = steps[currentIndex]
        guard !currentStep.requiresExplicitAnswerBeforeContinue || currentStep.isContinueAllowed else { return }
        view.endEditing(true)

        guard currentIndex < steps.count - 1 else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFinished?()
            return
        }

        transition(to: currentIndex + 1)
    }

    @objc private func backTapped() {
        guard !isTransitioning else { return }
        view.endEditing(true)

        if currentIndex == 0 {
            onBackToIntro?()
        } else {
            transition(to: currentIndex - 1)
        }
    }

    @objc private func backgroundTapped() {
        view.endEditing(true)
    }

    private func transition(to newIndex: Int) {
        guard !isTransitioning,
              newIndex >= 0,
              newIndex < steps.count,
              newIndex != currentIndex else { return }

        isTransitioning = true

        let movingForward = newIndex > currentIndex
        let oldStep = steps[currentIndex]
        let newStep = steps[newIndex]
        let direction: CGFloat = movingForward ? 1 : -1

        newStep.prepareForPresentation()
        newStep.alpha = 0
        newStep.transform = CGAffineTransform(translationX: 18 * direction, y: 0)
            .scaledBy(x: 0.982, y: 0.982)

        if newStep.superview == nil {
            contentContainer.addSubview(newStep)
            newStep.snp.makeConstraints { $0.edges.equalToSuperview() }
        }
        contentContainer.bringSubviewToFront(newStep)

        // Resolve the new pseudo-screen layout immediately, without animating any constraints.
        UIView.performWithoutAnimation {
            self.contentContainer.layoutIfNeeded()
        }

        currentIndex = newIndex

        // Chrome values update in place. There is no cross-dissolve/transform/layout animation
        // on the back button, step label, CTA or their parent view.
        stepLabel.text = "Step \(newIndex + 1) of \(steps.count)"
        primaryButton.setTitle(newIndex == steps.count - 1 ? "Finish" : "Continue", for: .normal)
        updatePrimaryButtonAvailability(for: newStep, animated: true)

        // The progress track stays fixed; only its inner fill grows/shrinks.
        progressView.setProgress(CGFloat(newIndex + 1) / CGFloat(steps.count), animated: true)

        UIView.animate(
            withDuration: onboardingTransitionDuration,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.16,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            oldStep.alpha = 0
            oldStep.transform = CGAffineTransform(translationX: -14 * direction, y: 0)
                .scaledBy(x: 0.99, y: 0.99)
            newStep.alpha = 1
            newStep.transform = .identity
        } completion: { [weak self] _ in
            oldStep.removeFromSuperview()
            oldStep.alpha = 1
            oldStep.transform = .identity
            self?.isTransitioning = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak newStep] in
            newStep?.animateCards()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
