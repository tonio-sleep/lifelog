import SwiftUI
import CoreLocation
import LocalAuthentication

/// Face ID / Touch ID helpers for the optional screen-lock shortcut.
enum Biometrics {
    static func availability() -> (available: Bool, name: String, symbol: String) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return (available, "Face ID", "faceid")
        case .touchID: return (available, "Touch ID", "touchid")
        default: return (false, "Biometrics", "lock")
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Everything Lifelog can ask for, in plain words, with the real current status.
/// Nothing is requested until a button here is pressed, and every item is optional.
struct PermissionsList: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var location: LocationService
    var includeBiometrics = true

    @State private var healthBusy = false
    @State private var healthMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            row(
                symbol: "bell",
                title: "Notifications",
                purpose: "Gentle reminders you set. They are scheduled on this device.",
                status: permissions.notifications.label,
                state: permissions.notifications,
                action: { Task { await permissions.requestNotifications() } }
            )
            Hairline()
            row(
                symbol: "location",
                title: "Location",
                purpose: "Optional visits and routes for your map. Stored only in your encrypted archive.",
                status: locationStatus,
                state: locationState,
                actionTitle: locationActionTitle,
                action: { location.requestPermission(always: true) }
            )
            if HealthService.isAvailable {
                Hairline()
                row(
                    symbol: "heart",
                    title: "Apple Health",
                    purpose: "Reads steps and sleep to fill in your days. iOS never tells apps whether read access was granted.",
                    status: env.healthConnected ? "Requested" : "Not asked yet",
                    state: env.healthConnected ? .granted : .notDetermined,
                    actionTitle: healthBusy ? "Working…" : (env.healthConnected ? "Sync now" : "Allow"),
                    action: { Task { await healthTapped() } }
                )
            }
            Hairline()
            row(
                symbol: "mic",
                title: "Microphone",
                purpose: "Only while you record a voice note. Recordings are encrypted on this device.",
                status: permissions.microphone.label,
                state: permissions.microphone,
                action: { Task { await permissions.requestMicrophone() } }
            )
            Hairline()
            row(
                symbol: "waveform",
                title: "Speech recognition",
                purpose: "Turns voice notes into text. Runs on this device when your language supports it.",
                status: permissions.speech.label,
                state: permissions.speech,
                action: { Task { await permissions.requestSpeech() } }
            )
            Hairline()
            row(
                symbol: "camera",
                title: "Camera",
                purpose: "Only when you take a photo or video inside Lifelog.",
                status: permissions.camera.label,
                state: permissions.camera,
                action: { Task { await permissions.requestCamera() } }
            )
            Hairline()
            row(
                symbol: "photo.on.rectangle",
                title: "Photo library",
                purpose: "No permission needed. You choose each photo in the system picker, and Lifelog sees only those.",
                status: "Not needed",
                state: .granted,
                action: {}
            )
            if includeBiometrics {
                let bio = Biometrics.availability()
                if bio.available {
                    Hairline()
                    row(
                        symbol: bio.symbol,
                        title: bio.name,
                        purpose: "Optional shortcut for your screen lock. Asked the first time you turn it on.",
                        status: env.biometricUnlockEnabled ? "On" : "Off",
                        state: env.biometricUnlockEnabled ? .granted : .notDetermined,
                        actionTitle: nil,
                        action: {}
                    )
                }
            }
            if let healthMessage {
                Text(healthMessage)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Space.sm)
            }
        }
        .task { await permissions.refresh() }
    }

    // MARK: Location mapping

    private var locationState: PermissionState {
        switch location.authorization {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        @unknown default: return .denied
        }
    }

    private var locationStatus: String {
        switch location.authorization {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using"
        case .denied: return "Not allowed"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private var locationActionTitle: String? {
        switch location.authorization {
        case .authorizedWhenInUse: return "Allow Always"
        case .authorizedAlways: return nil
        default: return nil
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(
        symbol: String,
        title: String,
        purpose: String,
        status: String,
        state: PermissionState,
        actionTitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(.body))
                .foregroundStyle(state == .granted ? Palette.moss : Palette.accent)
                .frame(width: 28)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    Text(status).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                }
                Text(purpose)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                actionButton(state: state, actionTitle: actionTitle, action: action)
            }
        }
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func actionButton(state: PermissionState, actionTitle: String?, action: @escaping () -> Void) -> some View {
        if let actionTitle {
            Button(actionTitle, action: action).buttonStyle(QuietButtonStyle())
        } else {
            switch state {
            case .notDetermined:
                Button("Allow", action: action).buttonStyle(QuietButtonStyle())
            case .denied, .restricted:
                Button("Open Settings") { PermissionCenter.openSystemSettings() }
                    .buttonStyle(QuietButtonStyle())
            case .granted, .unavailable:
                EmptyView()
            }
        }
    }

    private func healthTapped() async {
        healthBusy = true
        defer { healthBusy = false }
        healthMessage = env.healthConnected ? await env.syncHealth() : await env.connectHealth()
    }
}

/// The Settings destination that wraps the shared list.
struct PermissionsScreen: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                InfoLine(
                    text: "Lifelog works without any of these. If you decline one, only that feature is unavailable. iOS asks only once, so a declined permission can be changed in Settings.",
                    symbol: "hand.raised"
                )
                PermissionsList(permissions: env.permissions, location: env.location)
            }
            .padding(Space.page)
        }
        .paperScreen()
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
