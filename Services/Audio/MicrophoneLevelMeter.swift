import AVFoundation
import Foundation

@MainActor
final class MicrophoneLevelMeter: NSObject, ObservableObject {
    @Published private(set) var level: Double = 0

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.capture.microphone-level")
    private var activeDeviceID: String?

    func start(deviceID: String?) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            level = 0
            return
        }

        if session.isRunning, activeDeviceID == deviceID {
            return
        }

        stop()
        activeDeviceID = deviceID

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = microphoneDevice(id: deviceID),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else {
            session.commitConfiguration()
            level = 0
            return
        }

        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
        output.setSampleBufferDelegate(nil, queue: nil)
        activeDeviceID = nil
        level = 0
    }

    private func microphoneDevice(id: String?) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let id, let matchingDevice = devices.first(where: { $0.uniqueID == id }) {
            return matchingDevice
        }

        return AVCaptureDevice.default(for: .audio) ?? devices.first
    }
}

extension MicrophoneLevelMeter: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else {
            return
        }

        let sampleCount = length / MemoryLayout<Int16>.size
        guard sampleCount > 0 else {
            return
        }

        let sum = dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer -> Double in
            let samples = UnsafeBufferPointer(start: pointer, count: sampleCount)
            var sum: Double = 0
            for sample in samples {
                let normalized = Double(sample) / Double(Int16.max)
                sum += normalized * normalized
            }
            return sum
        }

        let rms = sqrt(sum / Double(sampleCount))
        let scaled = min(1, max(0, rms * 12))
        Task { @MainActor in
            self.level = (self.level * 0.65) + (scaled * 0.35)
        }
    }
}
