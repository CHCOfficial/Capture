import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Capture

@Suite(.serialized)
struct RecordingQualityTests {
    @Test func testNativePreservesRetinaPixelsAtBothFrameRates() {
        var configuration = RecordingConfiguration()
        configuration.resolution = .native
        for frameRate in FrameRate.allCases {
            configuration.frameRate = frameRate
            #expect(configuration.outputVideoSize(for: CGSize(width: 2560, height: 1440), pointPixelScale: 2) == CGSize(width: 5120, height: 2880))
        }
    }

    @Test func test1080pAt60FPSIsNotSilentlyReducedTo720p() {
        var configuration = RecordingConfiguration()
        configuration.frameRate = .sixty
        configuration.resolution = .p1080
        #expect(configuration.outputVideoSize(for: CGSize(width: 2560, height: 1440), pointPixelScale: 2) == CGSize(width: 1920, height: 1080))
    }

    @Test func testResolutionChoicesPreserveAspectRatioWithoutUpscaling() {
        let native = CGSize(width: 5120, height: 2880)
        #expect(ResolutionChoice.p2160.outputSize(for: native) == CGSize(width: 3840, height: 2160))
        #expect(ResolutionChoice.p1440.outputSize(for: native) == CGSize(width: 2560, height: 1440))
        #expect(ResolutionChoice.p720.outputSize(for: native) == CGSize(width: 1280, height: 720))
        #expect(ResolutionChoice.p2160.outputSize(for: CGSize(width: 1280, height: 800)) == CGSize(width: 1280, height: 800))
        #expect(ResolutionChoice.p1080.outputSize(for: CGSize(width: 1440, height: 2560)) == CGSize(width: 1080, height: 1920))
    }

    @Test func testRegionSizingUsesRetinaScaleAndEvenDimensions() {
        var configuration = RecordingConfiguration()
        configuration.resolution = .native
        #expect(configuration.outputVideoSize(for: CGSize(width: 400.5, height: 300.5), pointPixelScale: 2) == CGSize(width: 800, height: 600))
    }

    @Test func testAutomaticBitrateIncreasesWithQualityPixelsFrameRateAndCodec() {
        let size = CGSize(width: 1920, height: 1080)
        let high = RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .hevc)
        let balanced = RecordingQuality.balanced.videoBitRate(for: size, frameRate: .sixty, codec: .hevc)
        let efficient = RecordingQuality.efficient.videoBitRate(for: size, frameRate: .sixty, codec: .hevc)
        #expect(high > balanced)
        #expect(balanced > efficient)
        #expect(high > 25_000_000)
        #expect(high == 2 * RecordingQuality.high.videoBitRate(for: size, frameRate: .thirty, codec: .hevc))
        #expect(4 * high == RecordingQuality.high.videoBitRate(for: CGSize(width: 3840, height: 2160), frameRate: .sixty, codec: .hevc))
        #expect(RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .h264) > high)
    }

    @Test func testCustomBitrateOverridesPresetAndIsValidated() {
        let size = CGSize(width: 1920, height: 1080)
        for codec in VideoCodec.allCases {
            for quality in RecordingQuality.allCases {
                #expect(quality.videoBitRate(for: size, frameRate: .sixty, codec: codec, customMbps: 80.5) == 80_500_000)
            }
        }
        #expect(RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .hevc, customMbps: -5) == 1_000_000)
        #expect(RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .hevc, customMbps: 900) == 500_000_000)
        #expect(RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .hevc, customMbps: .nan) == RecordingQuality.high.videoBitRate(for: size, frameRate: .sixty, codec: .hevc))
    }

    @Test func testConfigurationCanReadLegacySettingsAndRoundTripCustomBitrate() throws {
        var configuration = RecordingConfiguration()
        configuration.customVideoBitRateMbps = 80.5
        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(RecordingConfiguration.self, from: encoded) == configuration)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "customVideoBitRateMbps")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        #expect(try JSONDecoder().decode(RecordingConfiguration.self, from: legacyData).customVideoBitRateMbps == nil)
    }

    @Test func testWriterProducesHEVCAtRequestedResolution() async throws {
        _ = try await verifyEncodedRecording(codec: .hevc, container: .mp4, customMbps: 25)
    }

    @Test func testWriterProducesH264AtRequestedResolution() async throws {
        _ = try await verifyEncodedRecording(codec: .h264, container: .mov, customMbps: nil)
    }

    @Test func testCustomBitrateAffectsHEVCEncodingOfMovingPictureInPicture() async throws {
        let lowRateBytes = try await verifyEncodedRecording(codec: .hevc, container: .mp4, customMbps: 1)
        let highRateBytes = try await verifyEncodedRecording(codec: .hevc, container: .mp4, customMbps: 40)
        #expect(highRateBytes > lowRateBytes * 2)
    }

    private func verifyEncodedRecording(codec: VideoCodec, container: OutputContainer, customMbps: Double?) async throws -> Int64 {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureQuality-\(UUID().uuidString).\(container.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        let size = CGSize(width: 1920, height: 1080)
        let writer = MediaWriter(outputURL: url, settings: MediaWriterSettings(
            videoSize: size,
            frameRate: .sixty,
            quality: .high,
            customVideoBitRateMbps: customMbps,
            container: container,
            codec: codec,
            audioMode: .none,
            selectedMicrophoneID: nil
        ))
        try await writer.prepare()
        for frame in 0..<36 {
            let sample = try makeVideoSample(width: 1920, height: 1080, frame: frame)
            try await writer.append(sample, kind: .screen)
            // Feed the real-time writer at its configured frame rate, without forcing dropped frames.
            try await Task.sleep(nanoseconds: 16_666_667)
        }
        let duration = try await writer.finish()
        #expect(duration > 0)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        let encodedSize = try await track.load(.naturalSize)
        #expect(encodedSize == size)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try #require(descriptions.first)
        let expectedCodec = codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        #expect(CMFormatDescriptionGetMediaSubType(description) == expectedCodec)

        // Read and decode a frame, so a valid container alone cannot pass this test.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        let decoded = try #require(output.copyNextSampleBuffer())
        let pixelBuffer = try #require(CMSampleBufferGetImageBuffer(decoded))
        #expect(CVPixelBufferGetWidth(pixelBuffer) == 1920)
        #expect(CVPixelBufferGetHeight(pixelBuffer) == 1080)
        reader.cancelReading()
        return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private func makeVideoSample(width: Int, height: Int, frame: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess)
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt32.self)
            row.initialize(repeating: 0xff181818, count: width)
            if y > height - 270 {
                for x in 0..<min(width, 480) {
                    // Moving high-frequency detail in a small PIP on a mostly static screen.
                    var noise = UInt32(truncatingIfNeeded: x * 73_856_093 ^ y * 19_349_663 ^ frame * 83_492_791)
                    noise ^= noise >> 13
                    noise &*= 1_274_126_177
                    row[x] = 0xff000000 | (noise & 0x00ffffff)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var description: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: CMTime(value: Int64(frame), timescale: 60), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
