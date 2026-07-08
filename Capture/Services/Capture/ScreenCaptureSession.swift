import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

final class ScreenCaptureSession: NSObject {
    private let sampleQueue = DispatchQueue(label: "com.capture.screen-samples", qos: .userInitiated)

    private var stream: SCStream?
    private var writer: MediaWriter?
    private var outputURL: URL?
    private var expectedVideoDimensions: (width: Int, height: Int)?
    private let lifecycleLock = NSLock()
    private var isStopping = false
    private var hasReportedFailure = false
    private let writerBacklogLock = NSLock()
    private var pendingWriterSamples: [CapturedSampleKind: Int] = [:]
    private let writerBacklogLimits: [CapturedSampleKind: Int] = [
        .screen: 2,
        .systemAudio: 12,
        .microphoneAudio: 12
    ]

    var onFailure: ((RecorderFailure) -> Void)?
    var onSourceBecameUnavailable: (() -> Void)?

    func start(target: ResolvedCaptureTarget, outputURL: URL, configuration: RecordingConfiguration) async throws -> CGSize {
        guard SystemCompatibility.isSupported else {
            throw RecorderFailure.unsupportedSystem(SystemCompatibility.unsupportedMessage)
        }

        self.outputURL = outputURL
        resetLifecycleForStart()
        resetWriterBacklog()

        let filter = makeFilter(for: target)
        let streamConfiguration = makeStreamConfiguration(for: target, filter: filter, recordingConfiguration: configuration)
        let videoSize = CGSize(width: streamConfiguration.width, height: streamConfiguration.height)
        expectedVideoDimensions = (streamConfiguration.width, streamConfiguration.height)

        let mediaWriter = MediaWriter(
            outputURL: outputURL,
            settings: MediaWriterSettings(
                videoSize: videoSize,
                frameRate: configuration.frameRate,
                quality: configuration.quality,
                container: configuration.outputContainer,
                codec: configuration.codec,
                audioMode: configuration.audioMode,
                selectedMicrophoneID: configuration.selectedMicrophoneID
            )
        )
        try await mediaWriter.prepare()
        writer = mediaWriter

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if configuration.audioMode.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        if configuration.audioMode.capturesMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        }

        self.stream = stream
        try await stream.startCapture()
        return videoSize
    }

    func pause() {
        Task {
            await writer?.pause()
        }
    }

    func resume() {
        Task {
            await writer?.resume()
        }
    }

    func stop() async throws -> TimeInterval {
        beginStopping()
        defer {
            writer = nil
            outputURL = nil
            expectedVideoDimensions = nil
            finishStopping()
            resetWriterBacklog()
        }

        let activeStream = stream
        stream = nil
        if let activeStream {
            try? await activeStream.stopCapture()
        }

        return try await writer?.finish() ?? 0
    }

    func cancel() {
        beginStopping()
        Task {
            let activeStream = stream
            stream = nil
            try? await activeStream?.stopCapture()
            await writer?.cancel()
            writer = nil
            outputURL = nil
            expectedVideoDimensions = nil
            finishStopping()
            resetWriterBacklog()
        }
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

    private func makeStreamConfiguration(
        for target: ResolvedCaptureTarget,
        filter: SCContentFilter,
        recordingConfiguration: RecordingConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let outputSize = resolvedOutputSize(for: target, filter: filter, recordingConfiguration: recordingConfiguration)

        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(recordingConfiguration.effectiveFrameRate.rawValue))
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = recordingConfiguration.mouse.showsCursor
        configuration.showMouseClicks = recordingConfiguration.mouse.showsClicks
        configuration.captureResolution = .nominal
        configuration.captureDynamicRange = .SDR
        configuration.shouldBeOpaque = true
        configuration.capturesAudio = recordingConfiguration.audioMode.capturesSystemAudio
        configuration.captureMicrophone = recordingConfiguration.audioMode.capturesMicrophone
        configuration.microphoneCaptureDeviceID = recordingConfiguration.selectedMicrophoneID
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        if case .display(_, _, let region) = target, let region {
            configuration.sourceRect = region
        }

        return configuration
    }

    private func resolvedOutputSize(
        for target: ResolvedCaptureTarget,
        filter: SCContentFilter,
        recordingConfiguration: RecordingConfiguration
    ) -> (width: Int, height: Int) {
        let contentRect = filter.contentRect.isEmpty ? target.sourceRect : filter.contentRect
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        var size = CGSize(width: contentRect.width * scale, height: contentRect.height * scale)

        if case .display(_, _, let region) = target, let region {
            size = CGSize(width: region.width * scale, height: region.height * scale)
        }

        if let maximumLongEdge = recordingConfiguration.maximumReliableLongEdge {
            let longEdge = max(size.width, size.height)
            if longEdge > maximumLongEdge, longEdge > 0 {
                let multiplier = maximumLongEdge / longEdge
                size = CGSize(width: size.width * multiplier, height: size.height * multiplier)
            }
        }

        return (width: Self.evenDimension(size.width), height: Self.evenDimension(size.height))
    }

    private func reserveWriterSlot(for kind: CapturedSampleKind) -> Bool {
        writerBacklogLock.lock()
        defer {
            writerBacklogLock.unlock()
        }

        let limit = writerBacklogLimits[kind] ?? 4
        let pending = pendingWriterSamples[kind] ?? 0
        guard pending < limit else {
            return false
        }

        pendingWriterSamples[kind] = pending + 1
        return true
    }

    private func releaseWriterSlot(for kind: CapturedSampleKind) {
        writerBacklogLock.lock()
        let pending = pendingWriterSamples[kind] ?? 0
        pendingWriterSamples[kind] = max(0, pending - 1)
        writerBacklogLock.unlock()
    }

    private func resetWriterBacklog() {
        writerBacklogLock.lock()
        pendingWriterSamples.removeAll(keepingCapacity: true)
        writerBacklogLock.unlock()
    }

    private func resetLifecycleForStart() {
        lifecycleLock.lock()
        isStopping = false
        hasReportedFailure = false
        lifecycleLock.unlock()
    }

    private func beginStopping() {
        lifecycleLock.lock()
        isStopping = true
        lifecycleLock.unlock()
    }

    private func finishStopping() {
        lifecycleLock.lock()
        isStopping = false
        lifecycleLock.unlock()
    }

    private func shouldIgnoreCallbacks() -> Bool {
        lifecycleLock.lock()
        let shouldIgnore = isStopping || hasReportedFailure
        lifecycleLock.unlock()
        return shouldIgnore
    }

    private func reportFailureOnce(_ failure: RecorderFailure) {
        lifecycleLock.lock()
        guard !isStopping, !hasReportedFailure else {
            lifecycleLock.unlock()
            return
        }

        hasReportedFailure = true
        isStopping = true
        lifecycleLock.unlock()
        onFailure?(failure)
    }

    private func reportSourceUnavailableOnce() {
        lifecycleLock.lock()
        guard !isStopping, !hasReportedFailure else {
            lifecycleLock.unlock()
            return
        }

        hasReportedFailure = true
        isStopping = true
        lifecycleLock.unlock()
        onSourceBecameUnavailable?()
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded(.toNearestOrAwayFromZero)))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    private func isWritableScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return false
        }

        if let expectedVideoDimensions {
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            guard width == expectedVideoDimensions.width, height == expectedVideoDimensions.height else {
                return false
            }
        }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return true
        }

        return status == .complete
    }
}

extension ScreenCaptureSession: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !shouldIgnoreCallbacks() else {
            return
        }

        let kind: CapturedSampleKind
        switch type {
        case .screen:
            guard isWritableScreenFrame(sampleBuffer) else {
                return
            }
            kind = .screen
        case .audio:
            kind = .systemAudio
        case .microphone:
            kind = .microphoneAudio
        @unknown default:
            return
        }

        guard reserveWriterSlot(for: kind) else {
            return
        }

        Task(priority: kind == .screen ? .userInitiated : .utility) {
            defer {
                releaseWriterSlot(for: kind)
            }

            do {
                try await writer?.append(sampleBuffer, kind: kind)
            } catch let failure as RecorderFailure {
                reportFailureOnce(failure)
            } catch {
                reportFailureOnce(.writerFailed(error.localizedDescription))
            }
        }
    }
}

extension ScreenCaptureSession: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !shouldIgnoreCallbacks() else {
            return
        }
        reportFailureOnce(.captureFailed(error.localizedDescription))
    }

    func streamDidBecomeInactive(_ stream: SCStream) {
        guard !shouldIgnoreCallbacks() else {
            return
        }
        reportSourceUnavailableOnce()
    }
}
