import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

enum CapturedSampleKind {
    case screen
    case systemAudio
    case microphoneAudio
}

struct MediaWriterSettings {
    var videoSize: CGSize
    var frameRate: FrameRate
    var quality: RecordingQuality
    var container: OutputContainer
    var codec: VideoCodec
    var audioMode: AudioMode
}

actor MediaWriter {
    private let outputURL: URL
    private let settings: MediaWriterSettings

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?

    private var hasStartedSession = false
    private var firstPresentationTime: CMTime?
    private var accumulatedPauseDuration = CMTime.zero
    private var pauseBeganAtPresentationTime: CMTime?
    private var isPaused = false
    private var lastPresentationTime = CMTime.zero

    init(outputURL: URL, settings: MediaWriterSettings) {
        self.outputURL = outputURL
        self.settings = settings
    }

    func prepare() throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: settings.container.avFileType)
        writer.shouldOptimizeForNetworkUse = true

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings())
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw RecorderFailure.writerFailed("The selected video settings are not supported.")
        }
        writer.add(videoInput)

        self.videoInput = videoInput

        if settings.audioMode.capturesSystemAudio {
            let input = audioInput(channelCount: 2)
            guard writer.canAdd(input) else {
                throw RecorderFailure.writerFailed("System audio cannot be added to this recording.")
            }
            writer.add(input)
            systemAudioInput = input
        }

        if settings.audioMode.capturesMicrophone {
            let input = audioInput(channelCount: 2)
            guard writer.canAdd(input) else {
                throw RecorderFailure.writerFailed("Microphone audio cannot be added to this recording.")
            }
            writer.add(input)
            microphoneAudioInput = input
        }

        self.writer = writer
    }

    func append(_ sampleBuffer: CMSampleBuffer, kind: CapturedSampleKind) throws {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        guard let presentationTime = sampleBuffer.presentationTimeStamp.validOrNil else {
            return
        }

        if isPaused {
            if pauseBeganAtPresentationTime == nil {
                pauseBeganAtPresentationTime = presentationTime
            }
            return
        }

        if let pauseBeganAtPresentationTime {
            let pauseDuration = CMTimeSubtract(presentationTime, pauseBeganAtPresentationTime)
            if pauseDuration.seconds.isFinite, pauseDuration > .zero {
                accumulatedPauseDuration = CMTimeAdd(accumulatedPauseDuration, pauseDuration)
            }
            self.pauseBeganAtPresentationTime = nil
        }

        if !hasStartedSession {
            guard kind == .screen else {
                return
            }
            try startSession(at: presentationTime)
        }

        guard let firstPresentationTime else {
            return
        }

        let offset = CMTimeAdd(firstPresentationTime, accumulatedPauseDuration)
        let retimedBuffer = try retimedSampleBuffer(sampleBuffer, subtracting: offset)
        let adjustedPresentationTime = CMTimeSubtract(presentationTime, offset)
        if adjustedPresentationTime > lastPresentationTime {
            lastPresentationTime = adjustedPresentationTime
        }

        guard adjustedPresentationTime >= .zero else {
            return
        }

        switch kind {
        case .screen:
            try append(retimedBuffer, to: videoInput, failureMessage: "Video encoder could not accept a frame.")
        case .systemAudio:
            try append(retimedBuffer, to: systemAudioInput, failureMessage: "System audio encoder could not accept audio.")
        case .microphoneAudio:
            try append(retimedBuffer, to: microphoneAudioInput, failureMessage: "Microphone encoder could not accept audio.")
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func finish() async throws -> TimeInterval {
        guard let writer else {
            return 0
        }

        guard hasStartedSession else {
            writer.cancelWriting()
            return 0
        }

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed {
            throw RecorderFailure.writerFailed(writer.error?.localizedDescription ?? "The recording could not be finalised.")
        }

        return max(0, CMTimeGetSeconds(lastPresentationTime))
    }

    func cancel() {
        writer?.cancelWriting()
    }

    private func startSession(at presentationTime: CMTime) throws {
        guard let writer else {
            throw RecorderFailure.writerFailed("The media writer was not prepared.")
        }

        firstPresentationTime = presentationTime
        guard writer.startWriting() else {
            throw RecorderFailure.writerFailed(writer.error?.localizedDescription ?? "The media writer could not start.")
        }
        writer.startSession(atSourceTime: .zero)
        hasStartedSession = true
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?, failureMessage: String) throws {
        guard let input else {
            return
        }

        if input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                throw RecorderFailure.writerFailed(writer?.error?.localizedDescription ?? failureMessage)
            }
        }
    }

    private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, subtracting offset: CMTime) throws -> CMSampleBuffer {
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else {
            return sampleBuffer
        }

        var timing = Array(repeating: CMSampleTimingInfo(), count: sampleCount)
        var timingEntries = 0
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: sampleCount,
            arrayToFill: &timing,
            entriesNeededOut: &timingEntries
        )

        guard timingStatus == noErr else {
            throw RecorderFailure.writerFailed("Capture could not read media timing information.")
        }

        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }

        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingEntries,
            sampleTimingArray: &timing,
            sampleBufferOut: &copiedBuffer
        )

        guard copyStatus == noErr, let copiedBuffer else {
            throw RecorderFailure.writerFailed("Capture could not retime media samples.")
        }

        return copiedBuffer
    }

    private func videoOutputSettings() -> [String: Any] {
        let width = Int(settings.videoSize.width.rounded(.toNearestOrAwayFromZero))
        let height = Int(settings.videoSize.height.rounded(.toNearestOrAwayFromZero))
        let bitRate = Int(Double(width * height * settings.frameRate.rawValue) * 0.07 * settings.quality.videoBitRateMultiplier)

        return [
            AVVideoCodecKey: settings.codec.avVideoCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(bitRate, 2_000_000),
                AVVideoExpectedSourceFrameRateKey: settings.frameRate.rawValue,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate.rawValue * 2
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
    }

    private func audioInput(channelCount: Int) -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: 192_000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }
}

private extension CMTime {
    var validOrNil: CMTime? {
        isValid && !seconds.isNaN ? self : nil
    }
}

private extension OutputContainer {
    var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }
}

private extension VideoCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }
}
