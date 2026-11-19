import SwiftUI

@main
struct LifelogApp: App {
    @UIApplicationDelegateAdaptor(LifelogAppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
    }
}
