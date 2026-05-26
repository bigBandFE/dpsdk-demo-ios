//
//  AppDelegate.swift
//  DPSDK-DEMO
//
//  Created by dragonpass on 2026/3/23.
//

import UIKit
import DPSDKKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        startSDK()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}

// MARK: - SDK Initialization

extension AppDelegate {

    @MainActor
    func startSDK(showLoading: Bool = false) {
        if showLoading { showLoadingOverlay() }

        DPSDK.start(clientId: "dpsdk-demo") { [weak self] success in
            guard success else {
                DPSDK.preOpen(appId: "lounge",keepWarmCount: 2)
                DPSDK.preOpen(appId: "fastTrack",keepWarmCount: 2)
                self?.hideLoadingOverlay()
                self?.showFailureAlert(message: "DPSDK start failed.")
                return
            }
            self?.requestAuthCode()
        }
    }
}

// MARK: - Auth Code

extension AppDelegate {

    @MainActor
    func requestAuthCode() {
        Task { [weak self] in
            do {
                let token = try await DemoDragonPassSSOClient.shared.getAndStoreAuthCode()
                await MainActor.run {
                    self?.hideLoadingOverlay()
                    DPSDK.shared.setAuthCode(token: token)
                }
            } catch {
                print("[DPSDK-DEMO][SSO] getAuthCode failed: \(error.localizedDescription)")
                await MainActor.run {
                    self?.hideLoadingOverlay()
                    self?.showFailureAlert(message: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Failure Alert

extension AppDelegate {

    @MainActor
    func showFailureAlert(message: String) {
        guard let presenter = topViewController else { return }

        let alert = UIAlertController(
            title: "Initialization Failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.startSDK(showLoading: true)
        })
        presenter.present(alert, animated: true)
    }
}

// MARK: - Loading Overlay

extension AppDelegate {

    private static let loadingTag = 90_0512

    @MainActor
    func showLoadingOverlay() {
        guard let window = keyWindow,
              window.viewWithTag(Self.loadingTag) == nil else { return }

        let overlay = UIView(frame: window.bounds)
        overlay.tag = Self.loadingTag
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.18)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        container.layer.cornerRadius = 14
        overlay.addSubview(container)

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = .white
        indicator.startAnimating()
        container.addSubview(indicator)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Getting auth code..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 172),
            container.heightAnchor.constraint(equalToConstant: 116),
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 14)
        ])

        window.addSubview(overlay)
    }

    @MainActor
    func hideLoadingOverlay() {
        keyWindow?.viewWithTag(Self.loadingTag)?.removeFromSuperview()
    }
}

// MARK: - Window Helpers

extension AppDelegate {

    @MainActor
    var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    @MainActor
    var topViewController: UIViewController? {
        guard let root = keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
