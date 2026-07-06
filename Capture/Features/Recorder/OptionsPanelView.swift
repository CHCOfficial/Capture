import SwiftUI

struct OptionsPanelView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @ObservedObject private var microphoneLevelMeter: MicrophoneLevelMeter

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        self._microphoneLevelMeter = ObservedObject(wrappedValue: viewModel.microphoneLevelMeter)
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
                Picker("Audio", selection: $viewModel.configuration.audioMode) {
                    ForEach(AudioMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if viewModel.configuration.audioMode.capturesMicrophone {
                    Picker("Input", selection: microphoneBinding) {
                        Text("System Default").tag("")
                        ForEach(viewModel.microphones) { microphone in
                            Text(microphone.name).tag(microphone.id)
                        }
                    }
                    .help("Choose the microphone to record.")

                    MicrophoneMeterView(level: microphoneLevelMeter.level)
                        .frame(height: 8)
                        .accessibilityLabel("Microphone level")
                }
            }
        } label: {
            Label("Audio", systemImage: "waveform")
        }
    }

    private var mouseSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show cursor", isOn: $viewModel.configuration.mouse.showsCursor)
                    .help("Include the pointer in recordings.")
                Toggle("Show clicks", isOn: $viewModel.configuration.mouse.showsClicks)
                    .help("Draw a click highlight around the pointer.")
            }
        } label: {
            Label("Mouse", systemImage: "cursorarrow.click")
        }
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

                Picker("Resolution", selection: $viewModel.configuration.resolution) {
                    ForEach(ResolutionChoice.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }

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
