import SwiftUI

struct SourcePickerView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @ObservedObject var sourceProvider: ShareableContentProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceControls
                .onChange(of: viewModel.selection.mode) { _, _ in
                    viewModel.selectDefaultSourceIfNeeded()
                }

            if viewModel.selection.mode == .region {
                RegionEditorView(viewModel: viewModel)
            }

            if let error = sourceProvider.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sourceControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                captureModePicker
                    .frame(minWidth: 460, idealWidth: 520)

                Spacer(minLength: 8)

                sourcePicker
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)

                refreshButton
            }

            VStack(alignment: .leading, spacing: 10) {
                captureModePicker

                HStack(spacing: 8) {
                    sourcePicker
                        .frame(maxWidth: .infinity)
                    refreshButton
                }
            }
        }
    }

    private var captureModePicker: some View {
        Picker("Capture", selection: $viewModel.selection.mode) {
            ForEach(CaptureMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbolName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Capture source type")
    }

    private var sourcePicker: some View {
        Picker("Source", selection: sourceIDBinding) {
            ForEach(sourceProvider.allSources(for: viewModel.selection.mode)) { source in
                Text(source.title)
                    .tag(source.id)
            }
        }
        .labelsHidden()
        .disabled(sourceProvider.allSources(for: viewModel.selection.mode).isEmpty)
        .help("Choose the display, window, or application to record.")
        .accessibilityLabel("Capture source")
    }

    private var refreshButton: some View {
        Button {
            Task {
                await sourceProvider.refresh()
                viewModel.selectDefaultSourceIfNeeded()
                await viewModel.refreshPreview()
            }
        } label: {
            Image(systemName: sourceProvider.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Refresh sources")
        .accessibilityLabel("Refresh sources")
    }

    private var sourceIDBinding: Binding<String> {
        Binding(
            get: { viewModel.selection.sourceID ?? "" },
            set: { viewModel.selection.sourceID = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct RegionEditorView: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                NumberField(title: "X", value: binding(\.origin.x))
                NumberField(title: "Y", value: binding(\.origin.y))
                NumberField(title: "W", value: binding(\.size.width))
                NumberField(title: "H", value: binding(\.size.height))
                Button {
                    resetRegion()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset region")
                .accessibilityLabel("Reset region")
            }
        }
        .font(.caption)
        .onAppear {
            if viewModel.selection.region == nil {
                resetRegion()
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double((viewModel.selection.region ?? fallbackRegion())[keyPath: keyPath]) },
            set: { newValue in
                var region = viewModel.selection.region ?? fallbackRegion()
                region[keyPath: keyPath] = CGFloat(newValue)
                region.size.width = max(64, region.size.width)
                region.size.height = max(64, region.size.height)
                viewModel.selection.region = region
            }
        )
    }

    private func resetRegion() {
        viewModel.selection.region = fallbackRegion()
    }

    private func fallbackRegion() -> CGRect {
        let frame = viewModel.sourceProvider.source(for: viewModel.selection)?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
        let width = max(640, frame.width * 0.55)
        let height = max(360, frame.height * 0.55)
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .accessibilityLabel(title)
        }
    }
}
