import UIKit

enum DemoHomeStyle {
    enum Color {
        static let background = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        static let title = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)
        static let text = UIColor(red: 0.39, green: 0.45, blue: 0.55, alpha: 1)
        static let muted = UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1)
        static let border = UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        static let primary = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)
        static let indigo = UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1)
        static let cyan = UIColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1)
        static let violet = UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1)
        static let rose = UIColor(red: 0.88, green: 0.11, blue: 0.28, alpha: 1)
        static let emerald = UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1)

        static func gradientStart(for app: DemoDPApp) -> UIColor {
            switch app {
            case .lounge:
                return indigo
            case .fastTrack:
                return rose
            }
        }

        static func gradientEnd(for app: DemoDPApp) -> UIColor {
            switch app {
            case .lounge:
                return cyan
            case .fastTrack:
                return violet
            }
        }
    }

    enum Spacing {
        static let section: CGFloat = 24
    }
}
