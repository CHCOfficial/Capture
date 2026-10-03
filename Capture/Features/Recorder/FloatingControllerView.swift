import SwiftUI

struct FloatingControllerView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var isCollapsed = false

    var body: some View {
        HStack(spacing: 10) {
            recordingDot

            if !isCollapsed {
                Text(viewModel.elapsedText)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .frame(width: 72, alignment: .leading)
                    .accessibilityLabel("Elapsed time \(viewModel.elapsedText)")

                Button {
                    viewModel.pauseOrResume()
                } label: {
                    Image(systemName: pauseIcon)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help(pauseHelp)
                .accessibilityLabel(pauseHelp)

                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Stop recording")
                .accessibilityLabel("Stop recording")

                Image(systemName: viewModel.configuration.audioMode.capturesMicrophone ? "mic.fill" : "mic.slash")
                    .foregroundStyle(viewModel.configuration.audioMode.capturesMicrophone ? .primary : .secondary)
                    .help(viewModel.configuration.audioMode.capturesMicrophone ? "Microphone on" : "Microphone off")
                    .accessibilityLabel(viewModel.configuration.audioMode.capturesMicrophone ? "Microphone on" : "Microphone off")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isCollapsed ? "Expand controller" : "Collapse controller")
            .accessibilityLabel(isCollapsed ? "Expand controller" : "Collapse controller")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.16))
        }
    }

    private var recordingDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 11, height: 11)
            .shadow(color: dotColor.opacity(0.45), radius: 5)
            .accessibilityLabel(dotLabel)
    }

    private var dotColor: Color {
        if case .paused = viewModel.state {
            return .orange
        }
        return .red
    }

    private var dotLabel: String {
        if case .paused = viewModel.state {
            return "Recording paused"
        }
        return "Recording"
    }

    private var pauseIcon: String {
        if case .paused = viewModel.state {
            return "play.fill"
        }
        return "pause.fill"
    }

    private var pauseHelp: String {
        if case .paused = viewModel.state {
            return "Resume recording"
        }
        return "Pause recording"
    }
}
