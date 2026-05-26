import UIKit

protocol DemoDPSDKHomeViewDelegate: AnyObject {
    func demoHomeView(_ view: DemoDPSDKHomeView, didTapApp app: DemoDPApp)
}

/// Home UI module. The only outward interaction is the DPApp button tap callback.
final class DemoDPSDKHomeView: UIView {
    weak var delegate: DemoDPSDKHomeViewDelegate?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyBackgroundGlow()
    }

    private func configure() {
        backgroundColor = DemoHomeStyle.Color.background
    }

    private func buildLayout() {
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        scrollView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = DemoHomeStyle.Spacing.section
        contentStack.alignment = .fill

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32)
        ])

        contentStack.addArrangedSubview(HeroSectionView())
        contentStack.addArrangedSubview(makeAppsSection())
    }

    private func makeAppsSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14

        let sectionLabel = UILabel()
        sectionLabel.text = "DPApp Ecosystem"
        sectionLabel.textColor = DemoHomeStyle.Color.muted
        sectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(sectionLabel)

        stack.addArrangedSubview(makeAppButton(for: .lounge))
        stack.addArrangedSubview(makeAppButton(for: .fastTrack))

        return stack
    }

    private func makeAppButton(for app: DemoDPApp) -> DemoDPAppButton {
        let button = DemoDPAppButton(app: app)
        button.addTarget(self, action: #selector(appButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func appButtonTapped(_ sender: DemoDPAppButton) {
        delegate?.demoHomeView(self, didTapApp: sender.app)
    }

    private func applyBackgroundGlow() {
        let glowName = "backgroundGlow"
        let glows = layer.sublayers?.filter { $0.name == glowName } ?? []

        if glows.count == 2 {
            glows[0].frame = CGRect(x: -120, y: 60, width: 320, height: 320)
            glows[1].frame = CGRect(x: bounds.width - 180, y: 360, width: 300, height: 300)
            return
        }

        layer.sublayers?.removeAll(where: { $0.name == glowName })

        let topGlow = makeGlowLayer(
            name: glowName,
            colors: [
                DemoHomeStyle.Color.violet.withAlphaComponent(0.22).cgColor,
                DemoHomeStyle.Color.cyan.withAlphaComponent(0.12).cgColor,
                UIColor.clear.cgColor
            ],
            frame: CGRect(x: -120, y: 60, width: 320, height: 320)
        )
        let bottomGlow = makeGlowLayer(
            name: glowName,
            colors: [
                DemoHomeStyle.Color.cyan.withAlphaComponent(0.16).cgColor,
                DemoHomeStyle.Color.indigo.withAlphaComponent(0.10).cgColor,
                UIColor.clear.cgColor
            ],
            frame: CGRect(x: bounds.width - 180, y: 360, width: 300, height: 300)
        )

        layer.insertSublayer(topGlow, at: 0)
        layer.insertSublayer(bottomGlow, at: 0)
    }

    private func makeGlowLayer(name: String, colors: [CGColor], frame: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.name = name
        layer.colors = colors
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.frame = frame
        layer.cornerRadius = min(frame.width, frame.height) / 2
        layer.opacity = 0.9
        layer.type = .radial
        return layer
    }
}
