import UIKit

final class HeroSectionView: UIStackView {
    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 18
        alignment = .fill

        addArrangedSubview(BadgeView())
        addArrangedSubview(makeTitleLabel())
        addArrangedSubview(makeDescriptionLabel())
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeTitleLabel() -> UILabel {
        let label = UILabel()
        label.attributedText = makeHeroTitle()
        label.numberOfLines = 0
        return label
    }

    private func makeDescriptionLabel() -> UILabel {
        let label = UILabel()
        label.text = "A polished host app demo for launching Dragonpass DPApps with native-feeling integration."
        label.textColor = DemoHomeStyle.Color.text
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func makeHeroTitle() -> NSAttributedString {
        let text = "Build travel experiences with DP SDK"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 36, weight: .heavy),
                .foregroundColor: DemoHomeStyle.Color.title,
                .kern: -0.8
            ]
        )

        if let range = text.range(of: "travel experiences") {
            attributed.addAttributes(
                [.foregroundColor: DemoHomeStyle.Color.indigo],
                range: NSRange(range, in: text)
            )
        }

        return attributed
    }
}

private final class BadgeView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.72)
        layer.cornerRadius = 16
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 1

        let dot = UIView()
        dot.backgroundColor = DemoHomeStyle.Color.emerald
        dot.layer.cornerRadius = 4

        let label = UILabel()
        label.text = "Dragonpass Hybrid SDK"
        label.textColor = DemoHomeStyle.Color.muted
        label.font = .systemFont(ofSize: 11, weight: .semibold)

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
