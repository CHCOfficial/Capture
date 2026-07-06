import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

struct CapturePermissionSnapshot: Equatable {
    var screenRecording: PermissionStatus
    var microphone: PermissionStatus
}

protocol PermissionAuthorizing {
    func snapshot() -> CapturePermissionSnapshot
    func refreshedSnapshot() async -> CapturePermissionSnapshot
    func requestScreenRecordingAccess() async -> Bool
    func requestMicrophoneAccess() async -> Bool
    func openScreenRecordingSettings()
    func openMicrophoneSettings()
}

final class SystemPermissionService: PermissionAuthorizing {
    private let defaults: UserDefaults
    private let screenRecordingRequestedKey = "Capture.screenRecordingPermissionRequested"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> CapturePermissionSnapshot {
        CapturePermissionSnapshot(
            screenRecording: screenRecordingStatus(),
            microphone: microphoneStatus()
        )
    }

    func refreshedSnapshot() async -> CapturePermissionSnapshot {
        var snapshot = snapshot()
        if snapshot.screenRecording != .granted {
            snapshot.screenRecording = await screenRecordingStatusFromShareableContent() ?? snapshot.screenRecording
        }
        return snapshot
    }

    func requestScreenRecordingAccess() async -> Bool {
        defaults.set(true, forKey: screenRecordingRequestedKey)
        return CGRequestScreenCaptureAccess()
    }

    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func openScreenRecordingSettings() {
        openSettingsPane("Privacy_ScreenCapture")
    }

    func openMicrophoneSettings() {
        openSettingsPane("Privacy_Microphone")
    }

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private func screenRecordingStatus() -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }

        return defaults.bool(forKey: screenRecordingRequestedKey) ? .denied : .notDetermined
    }

    private func screenRecordingStatusFromShareableContent() async -> PermissionStatus? {
        guard SystemCompatibility.isSupported else {
            return nil
        }

        do {
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            return nil
        }
    }

    private func openSettingsPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
