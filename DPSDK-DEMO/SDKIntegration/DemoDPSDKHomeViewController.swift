import UIKit
import DPSDKKit

// MARK: - DemoDPSDKHomeViewController

/// Entry-point controller for the demo host app.
///
/// Responsibility split:
/// - `DemoDPSDKHomeView` — UI presentation and interaction styling.
/// - This controller — receives button taps and will become the SDK opening point.
///
/// To add a new DPApp:
/// 1. Add a new case to the `DemoDPApp` enum.
/// 2. Add a corresponding button in `DemoDPSDKHomeView`.
/// 3. Add a new switch branch in `didTapApp` below.
final class DemoDPSDKHomeViewController: UIViewController {
    private let homeView = DemoDPSDKHomeView()

    // MARK: - Lifecycle

    override func loadView() {
        view = homeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        homeView.delegate = self
    }
}

// MARK: - DemoDPSDKHomeViewDelegate

extension DemoDPSDKHomeViewController: DemoDPSDKHomeViewDelegate {

    /// Handles a DPApp button tap.
    ///
    /// Reconnect this method to the SDK after running the install skill.
    func demoHomeView(_ view: DemoDPSDKHomeView, didTapApp app: DemoDPApp) {
        DPSDK.open(appId: app.appId, from: self)
    }
}
