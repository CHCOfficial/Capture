import AppKit
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

private let previewCIContext = CIContext(options: [.cacheIntermediates: false])

@MainActor
final class PreviewCaptureController: NSObject, ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var stateText = "Choose a source"
    @Published private(set) var isRunning = false

    private let sampleQueue = DispatchQueue(label: "com.capture.preview-samples", qos: .utility)
    private var stream: SCStream?
    private nonisolated(unsafe) var lastPublishedFrameTime = DispatchTime.now()

    func start(target: ResolvedCaptureTarget, configuration: RecordingConfiguration) async {
        guard SystemCompatibility.isSupported else {
            image = nil
            stateText = SystemCompatibility.unsupportedMessage
            return
        }

        await stop()
        stateText = "Loading preview..."

        do {
            let filter = makeFilter(for: target)
            let streamConfiguration = makeConfiguration(for: target, filter: filter, recordingConfiguration: configuration)
            let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            self.stream = stream
            try await stream.startCapture()
            isRunning = true
            stateText = ""
        } catch {
            image = nil
            isRunning = false
            stateText = error.localizedDescription
        }
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
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
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.queueDepth = 3
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
        if longEdge > 1200 {
            let multiplier = 1200 / longEdge
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
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = previewCIContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        Task { @MainActor in
            guard self.stream === stream else {
                return
            }
            self.image = nsImage
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
        guard elapsed >= 80_000_000 else {
            return false
        }

        lastPublishedFrameTime = now
        return true
    }
}

extension PreviewCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.image = nil
            self.stateText = error.localizedDescription
            self.isRunning = false
        }
    }
}
