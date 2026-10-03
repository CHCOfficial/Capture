import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if case .countdown = viewModel.state {
                    viewModel.cancelCountdown()
                } else if viewModel.state.isActive {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            } label: {
                Label(viewModel.primaryButtonTitle, systemImage: primaryIcon)
                    .frame(minWidth: 116)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(primaryTint)
            .disabled(!viewModel.state.isActive && !viewModel.canRecord)
            .help(primaryHelp)
            .accessibilityLabel(viewModel.primaryButtonTitle)

            Button {
                viewModel.pauseOrResume()
            } label: {
                Image(systemName: pauseIcon)
                    .frame(width: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!canPauseOrResume)
            .help(pauseHelp)
            .accessibilityLabel(pauseHelp)

            Button {
                viewModel.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.state.isActive)
            .help("Stop recording")
            .accessibilityLabel("Stop recording")

            Spacer()

            Label(viewModel.statusText, systemImage: statusIcon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(viewModel.statusText)
        }
        .padding(12)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var primaryIcon: String {
        switch viewModel.state {
        case .idle, .completed, .failed:
            return "record.circle"
        case .countdown:
            return "xmark.circle"
        default:
            return "stop.fill"
        }
    }

    private var primaryTint: Color {
        switch viewModel.state {
        case .idle, .completed, .failed:
            return .red
        case .countdown:
            return .orange
        default:
            return .red
        }
    }

    private var primaryHelp: String {
        viewModel.state.isActive ? "Stop and finalise the recording." : "Start recording the selected source."
    }

    private var canPauseOrResume: Bool {
        if case .recording = viewModel.state { return true }
        if case .paused = viewModel.state { return true }
        return false
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

    private var statusIcon: String {
        switch viewModel.state {
        case .recording: return "record.circle.fill"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        default: return "circle"
        }
    }
}

