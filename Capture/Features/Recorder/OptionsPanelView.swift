import SwiftUI

struct OptionsPanelView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @ObservedObject private var microphoneLevelMeter: MicrophoneLevelMeter
    @ObservedObject private var sourceProvider: ShareableContentProvider
    private let settingsLabelWidth: CGFloat = 82

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        self._microphoneLevelMeter = ObservedObject(wrappedValue: viewModel.microphoneLevelMeter)
        self._sourceProvider = ObservedObject(wrappedValue: viewModel.sourceProvider)
    }

    var body: some View {
        VStack(spacing: 12) {
            audioSection
            mouseSection
            qualitySection
            outputSection
        }
    }

    private var audioSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                settingsRow("Audio") {
                    Picker("Audio", selection: $viewModel.configuration.audioMode) {
                        ForEach(AudioMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.configuration.audioMode.capturesMicrophone {
                    settingsRow("Input") {
                        Picker("Input", selection: microphoneBinding) {
                            Text("System Default").tag("")
                            ForEach(viewModel.microphones) { microphone in
                                Text(microphone.name).tag(microphone.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Choose the microphone to record.")
                    }

                    HStack(spacing: 8) {
                        Color.clear
                            .frame(width: settingsLabelWidth, height: 0)
                        MicrophoneMeterView(level: microphoneLevelMeter.level)
                            .frame(height: 8)
                            .accessibilityLabel("Microphone level")
                    }
                }
            }
        } label: {
            Label("Audio", systemImage: "waveform")
        }
    }

    private var mouseSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                settingsRow("Cursor") {
                    Toggle("Show", isOn: $viewModel.configuration.mouse.showsCursor)
                        .help("Include the pointer in recordings.")
                }

                settingsRow("Clicks") {
                    Toggle("Show", isOn: $viewModel.configuration.mouse.showsClicks)
                        .help("Draw a click highlight around the pointer.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mouse", systemImage: "cursorarrow.click")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var qualitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Frame rate", selection: $viewModel.configuration.frameRate) {
                    ForEach(FrameRate.allCases) { frameRate in
                        Text(frameRate.title).tag(frameRate)
                    }
                }

                Picker("Quality", selection: $viewModel.configuration.quality) {
                    ForEach(RecordingQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .disabled(viewModel.configuration.customVideoBitRateMbps != nil)
                .help("Sets the automatic bitrate. A custom bitrate overrides this preset.")

                Picker("Resolution", selection: $viewModel.configuration.resolution) {
                    ForEach(ResolutionChoice.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .help("Native retains the source's full pixel resolution, including Retina detail. Other choices limit the long edge and preserve the aspect ratio.")

                HStack {
                    Picker("Format", selection: $viewModel.configuration.outputContainer) {
                        ForEach(OutputContainer.allCases) { container in
                            Text(container.title).tag(container)
                        }
                    }

                    Picker("Codec", selection: $viewModel.configuration.codec) {
                        ForEach(VideoCodec.allCases) { codec in
                            Text(codec.title).tag(codec)
                        }
                    }
                }

                Picker("Bitrate", selection: customBitRateEnabled) {
                    Text("Automatic").tag(false)
                    Text("Custom").tag(true)
                }
                .help("Automatic scales with quality, resolution, frame rate and codec. Custom sets an average target in Mbps.")

                if viewModel.configuration.customVideoBitRateMbps != nil {
                    settingsRow("Target") {
                        TextField("Mbps", value: customBitRate, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .accessibilityLabel("Custom video bitrate in Mbps")
                        Text("Mbps")
                        Stepper("Video bitrate", value: customBitRate, in: 1...500, step: 1)
                            .labelsHidden()
                    }
                }

                if let size = viewModel.outputVideoSize {
                    let bitRate = viewModel.configuration.videoBitRate(for: size)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Int(size.width)) × \(Int(size.height)) · \(viewModel.configuration.frameRate.title)")
                        Text("\(Double(bitRate) / 1_000_000, format: .number.precision(.fractionLength(0...1))) Mbps target · ~\(ByteCountFormatter.string(fromByteCount: Int64(bitRate) * 60 / 8, countStyle: .file))/min")
                        Text("Actual bitrate varies with screen activity.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        } label: {
            Label("Quality", systemImage: "slider.horizontal.3")
        }
    }

    private var outputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(viewModel.outputDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        viewModel.chooseOutputDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Choose output folder")
                    .accessibilityLabel("Choose output folder")
                }

                Picker("Countdown", selection: $viewModel.configuration.countdown) {
                    ForEach(CountdownChoice.allCases) { countdown in
                        Text(countdown.title).tag(countdown)
                    }
                }

                if let report = viewModel.diskSpaceReport {
                    Label(
                        ByteCountFormatter.string(fromByteCount: report.availableBytes, countStyle: .file) + " available",
                        systemImage: report.isLow ? "externaldrive.badge.exclamationmark" : "externaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(report.isLow ? .orange : .secondary)
                }
            }
        } label: {
            Label("Output", systemImage: "folder")
        }
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { viewModel.configuration.selectedMicrophoneID ?? "" },
            set: { viewModel.configuration.selectedMicrophoneID = $0.isEmpty ? nil : $0 }
        )
    }

    private var customBitRateEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.configuration.customVideoBitRateMbps != nil },
            set: { enabled in
                if enabled {
                    let automaticMbps = viewModel.outputVideoSize.map {
                        Double(viewModel.configuration.videoBitRate(for: $0)) / 1_000_000
                    } ?? 40
                    viewModel.configuration.customVideoBitRateMbps = min(max(automaticMbps.rounded(), 1), 500)
                } else {
                    viewModel.configuration.customVideoBitRateMbps = nil
                }
            }
        )
    }

    private var customBitRate: Binding<Double> {
        Binding(
            get: { viewModel.configuration.customVideoBitRateMbps ?? 40 },
            set: { value in
                guard value.isFinite else { return }
                viewModel.configuration.customVideoBitRateMbps = min(max(value, 1), 500)
            }
        )
    }

    private func settingsRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: settingsLabelWidth, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MicrophoneMeterView: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(level > 0.82 ? Color.orange : Color.green)
                    .frame(width: max(3, proxy.size.width * level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}
