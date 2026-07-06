import SwiftUI

struct PermissionBanner: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        if viewModel.permissions.screenRecording != .granted {
            banner(
                icon: "lock.rectangle",
                title: "Screen Recording permission is required",
                message: "Capture needs permission before it can list windows, show previews, or record.",
                primaryTitle: "Request",
                primaryAction: viewModel.requestScreenPermission,
                secondaryTitle: "Open Settings",
                secondaryAction: viewModel.openScreenRecordingSettings
            )
        } else if viewModel.configuration.audioMode.capturesMicrophone && viewModel.permissions.microphone != .granted {
            banner(
                icon: "mic.slash",
                title: "Microphone access is off",
                message: "Turn it on to record microphone audio, or choose another audio mode.",
                primaryTitle: "Request",
                primaryAction: viewModel.requestMicrophonePermission,
                secondaryTitle: "Open Settings",
                secondaryAction: viewModel.openMicrophoneSettings
            )
        }
    }

    private func banner(
        icon: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(secondaryTitle, action: secondaryAction)
                .controlSize(.small)
            Button(primaryTitle, action: primaryAction)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

