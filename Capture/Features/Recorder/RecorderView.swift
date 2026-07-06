import AppKit
import SwiftUI

struct RecorderView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @ObservedObject var appIconController: AppIconController
    @Environment(\.openSettings) private var openSettings
    @State private var recordingToRename: Recording?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 14) {
                PermissionBanner(viewModel: viewModel)

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 12) {
                        SourcePickerView(viewModel: viewModel, sourceProvider: viewModel.sourceProvider)
                        LivePreviewView(previewController: viewModel.previewController)
                            .frame(minHeight: 280)
                        RecordingControlsView(viewModel: viewModel)
                    }

                    OptionsPanelView(viewModel: viewModel)
                        .frame(width: 284)
                }

                CompletionActionsView(
                    viewModel: viewModel,
                    recordingToRename: $recordingToRename,
                    renameText: $renameText
                )

                RecentRecordingsView(
                    viewModel: viewModel,
                    recordingToRename: $recordingToRename,
                    renameText: $renameText
                )

                HStack {
                    Spacer()
                    supportButton
                }
            }
            .padding(18)
        }
        .background(.regularMaterial)
        .frame(minWidth: 760, minHeight: 590)
        .alert("Capture", isPresented: alertBinding) {
            Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .sheet(item: $recordingToRename) { recording in
            RenameRecordingSheet(
                recording: recording,
                text: $renameText,
                onCancel: { recordingToRename = nil },
                onRename: {
                    viewModel.rename(recording, to: renameText)
                    recordingToRename = nil
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            headerIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("Capture")
                    .font(.headline)
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(viewModel.elapsedText)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .accessibilityLabel("Elapsed time \(viewModel.elapsedText)")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var supportButton: some View {
        Button {
            NSWorkspace.shared.open(CaptureLinks.buyMeACoffeeURL)
        } label: {
            Label("Buy me a coffee", systemImage: "cup.and.saucer")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
        .help("Support Capture on Buy Me a Coffee")
        .accessibilityLabel("Support Capture on Buy Me a Coffee")
    }

    @ViewBuilder
    private var headerIcon: some View {
        if let image = appIconController.previewImage(for: appIconController.selectedIcon) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "record.circle")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.state.isActive ? .red : .primary)
                .accessibilityHidden(true)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.alertMessage = nil
                }
            }
        )
    }
}

private struct RenameRecordingSheet: View {
    let recording: Recording
    @Binding var text: String
    var onCancel: () -> Void
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Recording")
                .font(.headline)
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    text = recording.url.deletingPathExtension().lastPathComponent
                }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Rename", action: onRename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
