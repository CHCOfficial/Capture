import CoreGraphics
import Foundation

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case display
    case window
    case application
    case region

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "Display"
        case .window: return "Window"
        case .application: return "Application"
        case .region: return "Region"
        }
    }

    var symbolName: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .application: return "app.dashed"
        case .region: return "selection.pin.in.out"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable, Codable {
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) FPS" }
}

enum RecordingQuality: String, CaseIterable, Identifiable, Codable {
    case efficient
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .efficient: return "Efficient"
        case .balanced: return "Balanced"
        case .high: return "High"
        }
    }

    var videoBitRateMultiplier: Double {
        switch self {
        case .efficient: return 0.55
        case .balanced: return 0.85
        case .high: return 1.2
        }
    }
}

enum ResolutionChoice: String, CaseIterable, Identifiable, Codable {
    case native
    case p1080
    case p720

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return "Native"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }

    var maximumLongEdge: CGFloat? {
        switch self {
        case .native: return nil
        case .p1080: return 1920
        case .p720: return 1280
        }
    }
}

enum AudioMode: String, CaseIterable, Identifiable, Codable {
    case none
    case system
    case microphone
    case systemAndMicrophone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .system: return "System"
        case .microphone: return "Mic"
        case .systemAndMicrophone: return "System + Mic"
        }
    }

    var capturesSystemAudio: Bool {
        self == .system || self == .systemAndMicrophone
    }

    var capturesMicrophone: Bool {
        self == .microphone || self == .systemAndMicrophone
    }
}

enum OutputContainer: String, CaseIterable, Identifiable, Codable {
    case mp4
    case mov

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var title: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable, Codable {
    case hevc
    case h264

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        }
    }
}

enum CountdownChoice: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }
    var title: String { rawValue == 0 ? "Off" : "\(rawValue)s" }
}

struct MouseCaptureOptions: Equatable, Codable {
    var showsCursor: Bool = true
    var showsClicks: Bool = false
}

struct RecordingConfiguration: Equatable, Codable {
    var frameRate: FrameRate = .thirty
    var quality: RecordingQuality = .balanced
    var resolution: ResolutionChoice = .p1080
    var audioMode: AudioMode = .none
    var selectedMicrophoneID: String?
    var mouse: MouseCaptureOptions = MouseCaptureOptions()
    var countdown: CountdownChoice = .three
    var hidesMainWindowDuringCapture: Bool = true
    var showsStatusItem: Bool = true
    var outputContainer: OutputContainer = .mp4
    var codec: VideoCodec = .h264
    var includeCaptureAppInDisplayRecordings: Bool = false
}

extension RecordingConfiguration {
    var effectiveFrameRate: FrameRate {
        frameRate
    }

    var maximumReliableLongEdge: CGFloat? {
        let userMaximumLongEdge = resolution.maximumLongEdge
        let reliabilityMaximumLongEdge: CGFloat = frameRate == .sixty ? 1280 : 1920

        guard let userMaximumLongEdge else {
            return reliabilityMaximumLongEdge
        }

        return min(userMaximumLongEdge, reliabilityMaximumLongEdge)
    }
}

enum CaptureSourceKind: String, Codable {
    case display
    case window
    case application
}

struct CaptureSource: Identifiable, Hashable, Codable {
    var id: String
    var kind: CaptureSourceKind
    var title: String
    var subtitle: String
    var displayID: UInt32?
    var windowID: UInt32?
    var processID: Int32?
    var bundleIdentifier: String?
    var frame: CGRect

    var iconName: String {
        switch kind {
        case .display: return "display"
        case .window: return "macwindow"
        case .application: return "app"
        }
    }
}

struct CaptureSelection: Equatable, Codable {
    var mode: CaptureMode = .display
    var sourceID: CaptureSource.ID?
    var region: CGRect?
}

struct Recording: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var url: URL
    var createdAt: Date
    var duration: TimeInterval
    var byteCount: Int64
    var sourceTitle: String

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct DiskSpaceReport: Equatable {
    var availableBytes: Int64
    var isLow: Bool
}

enum RecorderFailure: Error, Equatable, LocalizedError {
    case unsupportedSystem(String)
    case missingScreenRecordingPermission
    case missingMicrophonePermission
    case noCaptureSource
    case sourceUnavailable(String)
    case destinationUnavailable(String)
    case lowDiskSpace(availableBytes: Int64)
    case writerFailed(String)
    case captureFailed(String)
    case invalidTransition(from: String, to: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem(let message):
            return message
        case .missingScreenRecordingPermission:
            return "Screen Recording permission is required to capture your screen."
        case .missingMicrophonePermission:
            return "Microphone permission is required when microphone capture is enabled."
        case .noCaptureSource:
            return "Choose something to record first."
        case .sourceUnavailable(let message):
            return message
        case .destinationUnavailable(let message):
            return message
        case .lowDiskSpace(let availableBytes):
            return "Available disk space is low (\(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)))."
        case .writerFailed(let message):
            return message
        case .captureFailed(let message):
            return message
        case .invalidTransition(let from, let to):
            return "Cannot move from \(from) to \(to)."
        case .cancelled:
            return "Recording was cancelled."
        }
    }
}
