import Foundation

enum SystemCompatibility {
    static let minimumSupportedVersion = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)

    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumSupportedVersion)
    }

    static var unsupportedMessage: String {
        "Capture requires macOS 15 or later for reliable ScreenCaptureKit recording with microphone and mouse-click capture."
    }
}

