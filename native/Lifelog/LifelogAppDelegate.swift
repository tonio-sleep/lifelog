import Foundation
import UIKit

/// Starts background-capable location monitoring at process launch. SwiftUI
/// view appearance is not guaranteed during a background location relaunch.
final class LifelogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            let environment = AppEnvironment.shared
            if environment.settings.locationTrackingEnabled {
                environment.location.start()
            }
        }
        return true
    }
}
