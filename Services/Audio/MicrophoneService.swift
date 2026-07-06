import AVFoundation
import Foundation

struct MicrophoneDevice: Identifiable, Equatable {
    var id: String
    var name: String
}

protocol MicrophoneProviding {
    func availableMicrophones() -> [MicrophoneDevice]
}

final class SystemMicrophoneProvider: MicrophoneProviding {
    func availableMicrophones() -> [MicrophoneDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        return discovery.devices
            .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

