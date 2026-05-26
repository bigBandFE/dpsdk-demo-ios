import Foundation

final class DemoLoginSessionStore {
    static let shared = DemoLoginSessionStore()

    private let h5TokenKey = "demo.login.h5token"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func storeBridgeSession(token: String) {
        defaults.set(token, forKey: h5TokenKey)
    }

    var h5Token: String? {
        let token = defaults.string(forKey: h5TokenKey)
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}
