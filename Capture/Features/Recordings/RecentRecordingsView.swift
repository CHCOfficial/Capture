import SwiftUI

struct RecentRecordingsView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @Binding var recordingToRename: Recording?
    @Binding var renameText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Task { await viewModel.loadRecentRecordingsForUI() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh recent recordings")
                .accessibilityLabel("Refresh recent recordings")
            }

            if viewModel.recentRecordings.isEmpty {
                Text("Completed recordings will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.recentRecordings) { recording in
                            RecentRecordingTile(
                                recording: recording,
                                viewModel: viewModel,
                                onRename: {
                                    renameText = recording.url.deletingPathExtension().lastPathComponent
                                    recordingToRename = recording
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RecentRecordingTile: View {
    let recording: Recording
    @ObservedObject var viewModel: RecorderViewModel
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                Text(recording.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                iconButton("play.rectangle", "Preview") { viewModel.preview(recording) }
                iconButton("folder", "Reveal in Finder") { viewModel.revealInFinder(recording) }
                iconButton("doc.on.doc", "Copy Path") { viewModel.copyPath(recording) }
                iconButton("square.and.pencil", "Rename") { onRename() }
                iconButton("square.and.arrow.up", "Share") { viewModel.share(recording) }
                iconButton("trash", "Delete") { viewModel.delete(recording) }
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct CompletionActionsView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @Binding var recordingToRename: Recording?
    @Binding var renameText: String

    var body: some View {
        if case .completed(let recording) = viewModel.state {
            HStack(spacing: 10) {
                Label("Saved \(recording.displayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Reveal") { viewModel.revealInFinder(recording) }
                Button("Preview") { viewModel.preview(recording) }
                Button("Rename") {
                    renameText = recording.displayName
                    recordingToRename = recording
                }
                Button("Copy Path") { viewModel.copyPath(recording) }
                Button("Share") { viewModel.share(recording) }
                Button(role: .destructive) { viewModel.delete(recording) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .accessibilityLabel("Delete")
            }
            .font(.subheadline)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

