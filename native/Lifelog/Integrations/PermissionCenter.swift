import Foundation
import AVFoundation
import Speech
import UserNotifications
import UIKit

enum PermissionState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable

    var isGranted: Bool { self == .granted }
    var canPrompt: Bool { self == .notDetermined }
    /// The system will not show a prompt again; the person must use Settings.
    var needsSettings: Bool { self == .denied || self == .restricted }

    var label: String {
        switch self {
        case .notDetermined: return "Not asked yet"
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        }
    }
}

// Callback-based system APIs are bridged from plain (non-isolated) functions so
// their completion handlers are never treated as main-actor closures.

private func requestRecordPermission() async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}

private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
}

/// One place that knows how to ask for, and report on, the permissions Lifelog
/// can use. Location and Health have their own services because their state is
/// richer; this covers everything else.
///
/// Every permission is optional. Lifelog asks only when a feature needs it, and
/// the app works without any of them.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var notifications: PermissionState = .notDetermined
    @Published private(set) var microphone: PermissionState = .notDetermined
    @Published private(set) var speech: PermissionState = .notDetermined
    @Published private(set) var camera: PermissionState = .notDetermined

    var cameraHardwareAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = Self.state(settings.authorizationStatus)
        microphone = Self.microphoneState()
        speech = Self.state(SFSpeechRecognizer.authorizationStatus())
        camera = cameraHardwareAvailable
            ? Self.state(AVCaptureDevice.authorizationStatus(for: .video))
            : .unavailable
    }

    // MARK: Requests

    @discardableResult
    func requestNotifications() async -> Bool {
        let granted = await NotificationService.requestAuthorization()
        await refresh()
        return granted
    }

    @discardableResult
    func requestMicrophone() async -> Bool {
        if microphone == .granted { return true }
        if microphone.needsSettings { return false }
        let granted = await requestRecordPermission()
        microphone = granted ? .granted : .denied
        return granted
    }

    @discardableResult
    func requestSpeech() async -> Bool {
        if speech == .granted { return true }
        if speech.needsSettings { return false }
        let status = await requestSpeechAuthorization()
        speech = Self.state(status)
        return speech == .granted
    }

    @discardableResult
    func requestCamera() async -> Bool {
        guard cameraHardwareAvailable else { camera = .unavailable; return false }
        if camera == .granted { return true }
        if camera.needsSettings { return false }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        camera = granted ? .granted : .denied
        return granted
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Mapping

    private static func state(_ status: UNAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .granted
        @unknown default: return .denied
        }
    }

    private static func state(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .granted
        @unknown default: return .denied
        }
    }

    private static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .granted
        @unknown default: return .denied
        }
    }

    private static func microphoneState() -> PermissionState {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined: return .notDetermined
        case .denied: return .denied
        case .granted: return .granted
        @unknown default: return .denied
        }
    }
}
