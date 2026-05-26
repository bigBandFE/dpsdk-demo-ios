import Foundation

/// DPApp entries configured by this demo host project.
///
/// In a real host app, this is the place to map product modules to the appId
/// values assigned by your integration configuration. The view layer only
/// renders these entries; the controller handles the selected item.
enum DemoDPApp {
    case lounge
    case fastTrack

    private var configuration: DemoDPAppConfiguration {
        switch self {
        case .lounge:
            return .lounge
        case .fastTrack:
            return .fastTrack
        }
    }

    var appId: String {
        configuration.appId
    }

    var title: String {
        configuration.title
    }

    var subtitle: String {
        configuration.subtitle
    }

    var iconName: String {
        configuration.iconName
    }
}

private struct DemoDPAppConfiguration {
    let appId: String
    let title: String
    let subtitle: String
    let iconName: String

    static let lounge = DemoDPAppConfiguration(
        appId: "lounge",
        title: "Lounge",
        subtitle: "Launch lounge discovery and booking flows.",
        iconName: "LoungeIcon"
    )

    static let fastTrack = DemoDPAppConfiguration(
        appId: "fastTrack",
        title: "Fast Track",
        subtitle: "Open priority airport security experiences.",
        iconName: "FastTrackIcon"
    )
}
