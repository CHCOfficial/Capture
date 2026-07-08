import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

private let previewCIContext = CIContext(options: [.cacheIntermediates: false])
private let previewColorSpace = CGColorSpaceCreateDeviceRGB()
private let previewFrameIntervalNanoseconds: UInt64 = 33_000_000
private let previewCaptureMaximumLongEdge: CGFloat = 720

@MainActor
final class PreviewCaptureController: NSObject, ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var stateText = "Choose a source"
    @Published private(set) var isRunning = false

    private let sampleQueue = DispatchQueue(label: "com.capture.preview-samples", qos: .userInitiated)
    private var stream: SCStream?
    private var lifecycleToken = UUID()
    private nonisolated(unsafe) var lastPublishedFrameTime = DispatchTime.now()
    private let frameStateLock = NSLock()
    private nonisolated(unsafe) var hasFrameAwaitingMainActor = false

    func start(target: ResolvedCaptureTarget, configuration: RecordingConfiguration) async {
        guard SystemCompatibility.isSupported else {
            image = nil
            stateText = SystemCompatibility.unsupportedMessage
            return
        }

        let token = UUID()
        lifecycleToken = token
        await stopCurrentStream()
        guard lifecycleToken == token else {
            return
        }

        stateText = "Loading preview..."

        do {
            let filter = makeFilter(for: target)
            let streamConfiguration = makeConfiguration(for: target, filter: filter, recordingConfiguration: configuration)
            let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            guard lifecycleToken == token else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            lastPublishedFrameTime = DispatchTime(uptimeNanoseconds: 0)
            try await stream.startCapture()
            guard lifecycleToken == token else {
                try? await stream.stopCapture()
                return
            }
            isRunning = true
            stateText = ""
        } catch {
            guard lifecycleToken == token else {
                return
            }
            image = nil
            isRunning = false
            stateText = error.localizedDescription
        }
    }

    func stop() async {
        lifecycleToken = UUID()
        await stopCurrentStream()
    }

    private func stopCurrentStream() async {
        let currentStream = stream
        stream = nil
        if let currentStream {
            try? await currentStream.stopCapture()
        }
        if currentStream != nil {
            releaseFrameSlot()
        }
        isRunning = false
    }

    private func makeFilter(for target: ResolvedCaptureTarget) -> SCContentFilter {
        switch target {
        case .display(let display, let excludedApplications, _):
            return SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        case .application(let application, let display, let excludedWindows):
            return SCContentFilter(display: display, including: [application], exceptingWindows: excludedWindows)
        }
    }

    private func makeConfiguration(
        for target: ResolvedCaptureTarget,
        filter: SCContentFilter,
        recordingConfiguration: RecordingConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let size = previewSize(for: target, filter: filter)
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .nominal
        configuration.showsCursor = recordingConfiguration.mouse.showsCursor
        configuration.showMouseClicks = recordingConfiguration.mouse.showsClicks
        if case .display(_, _, let region) = target, let region {
            configuration.sourceRect = region
        }
        return configuration
    }

    private func previewSize(for target: ResolvedCaptureTarget, filter: SCContentFilter) -> (width: Int, height: Int) {
        let contentRect = filter.contentRect.isEmpty ? target.sourceRect : filter.contentRect
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        var size = CGSize(width: contentRect.width * scale, height: contentRect.height * scale)

        if case .display(_, _, let region) = target, let region {
            size = CGSize(width: region.width * scale, height: region.height * scale)
        }

        let longEdge = max(size.width, size.height)
        if longEdge > previewCaptureMaximumLongEdge {
            let multiplier = previewCaptureMaximumLongEdge / longEdge
            size = CGSize(width: size.width * multiplier, height: size.height * multiplier)
        }

        return (width: Self.evenDimension(size.width), height: Self.evenDimension(size.height))
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded(.toNearestOrAwayFromZero)))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}

extension PreviewCaptureController: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              isCompleteFrame(sampleBuffer),
              shouldPublishFrame(),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              reserveFrameSlot() else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = previewCIContext.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .BGRA8,
            colorSpace: previewColorSpace
        ) else {
            releaseFrameSlot()
            return
        }

        Task { @MainActor in
            defer {
                self.releaseFrameSlot()
            }

            guard self.stream === stream else {
                return
            }
            self.image = cgImage
        }
    }

    private nonisolated func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return true
        }

        return status == .complete || status == .started
    }

    private nonisolated func shouldPublishFrame() -> Bool {
        let now = DispatchTime.now()
        let elapsed = now.uptimeNanoseconds - lastPublishedFrameTime.uptimeNanoseconds
        guard elapsed >= previewFrameIntervalNanoseconds else {
            return false
        }

        lastPublishedFrameTime = now
        return true
    }

    private nonisolated func reserveFrameSlot() -> Bool {
        frameStateLock.lock()
        defer {
            frameStateLock.unlock()
        }

        guard !hasFrameAwaitingMainActor else {
            return false
        }

        hasFrameAwaitingMainActor = true
        return true
    }

    private nonisolated func releaseFrameSlot() {
        frameStateLock.lock()
        hasFrameAwaitingMainActor = false
        frameStateLock.unlock()
    }
}

extension PreviewCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else {
                return
            }
            self.image = nil
            self.stateText = error.localizedDescription
            self.isRunning = false
        }
    }
}
