import UIKit

final class DemoDPAppButton: UIControl {
    let app: DemoDPApp

    private let hitTestOutsets = UIEdgeInsets(top: -8, left: -8, bottom: -8, right: -8)

    init(app: DemoDPApp) {
        self.app = app
        super.init(frame: .zero)
        configureCard()
        buildContent()
        bindTouchHandlers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: hitTestOutsets).contains(point)
    }

    private func configureCard() {
        backgroundColor = UIColor.white.withAlphaComponent(0.88)
        layer.cornerRadius = 24
        layer.borderColor = DemoHomeStyle.Color.border.cgColor
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 10)
        isExclusiveTouch = true
        accessibilityTraits.insert(.button)
        accessibilityLabel = app.title
    }

    private func buildContent() {
        // Icon container: 48x48 rounded square background matching RN style
        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor(red: 0.039, green: 0.137, blue: 0.204, alpha: 0.05)
        iconContainer.layer.cornerRadius = 16
        iconContainer.clipsToBounds = true

        let iconView = UIImageView(image: UIImage(named: app.iconName))
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(red: 0.039, green: 0.137, blue: 0.204, alpha: 1.0)
        iconContainer.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48)
        ])

        let titleLabel = UILabel()
        titleLabel.text = app.title
        titleLabel.textColor = DemoHomeStyle.Color.title
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = app.subtitle
        subtitleLabel.textColor = DemoHomeStyle.Color.text
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.numberOfLines = 0

        let appIdBadge = AppIdBadgeView(appId: app.appId)

        let chevronLabel = UILabel()
        chevronLabel.text = "›"
        chevronLabel.textColor = DemoHomeStyle.Color.muted
        chevronLabel.font = .systemFont(ofSize: 32, weight: .regular)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, appIdBadge])
        textStack.axis = .vertical
        textStack.spacing = 7
        textStack.alignment = .leading

        let row = UIStackView(arrangedSubviews: [iconContainer, textStack, chevronLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 104),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    private func bindTouchHandlers() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchCancel), for: [.touchCancel, .touchDragExit])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside])
    }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            self.alpha = 0.92
        }
    }

    @objc private func touchCancel() {
        restoreCard()
    }

    @objc private func touchUp() {
        restoreCard()
    }

    private func restoreCard() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}

private final class AppIdBadgeView: UIView {
    init(appId: String) {
        super.init(frame: .zero)
        backgroundColor = DemoHomeStyle.Color.primary.withAlphaComponent(0.06)
        layer.cornerRadius = 12
        layer.borderColor = DemoHomeStyle.Color.border.cgColor
        layer.borderWidth = 1

        let label = UILabel()
        label.text = "SDK appId: \(appId)"
        label.textColor = DemoHomeStyle.Color.primary
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
