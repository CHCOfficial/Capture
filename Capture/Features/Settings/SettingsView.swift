import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @ObservedObject var appIconController: AppIconController
    @ObservedObject private var hotkeys: HotkeyPreferences

    init(viewModel: RecorderViewModel, appIconController: AppIconController) {
        self.viewModel = viewModel
        self.appIconController = appIconController
        self._hotkeys = ObservedObject(wrappedValue: viewModel.hotkeyPreferences)
    }

    var body: some View {
        Form {
            Section("App Icon") {
                AppIconPickerView(appIconController: appIconController)
                Text("macOS updates the Dock icon immediately. Finder uses the bundle icon from the app copy on disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Hide main window while recording", isOn: $viewModel.configuration.hidesMainWindowDuringCapture)
                    .help("Keep the main Capture window out of recordings.")

                Toggle("Show menu bar status item", isOn: $viewModel.configuration.showsStatusItem)
                    .help("Add recording controls to the menu bar.")

                Toggle("Include Capture in display recordings", isOn: $viewModel.configuration.includeCaptureAppInDisplayRecordings)
                    .help("Disabled by default so Capture controls are not recorded accidentally.")
            }

            Section("Output") {
                HStack {
                    Text(viewModel.outputDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...", action: viewModel.chooseOutputDirectory)
                }
            }

            Section("Shortcuts") {
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorderButton(action: action, preferences: hotkeys)
                    }
                }

                Button("Reset Shortcuts") {
                    hotkeys.reset()
                }
            }

            Section("Permissions") {
                HStack {
                    Label("Screen Recording", systemImage: permissionIcon(viewModel.permissions.screenRecording))
                    Spacer()
                    Button("Open Settings", action: viewModel.openScreenRecordingSettings)
                }
                HStack {
                    Label("Microphone", systemImage: permissionIcon(viewModel.permissions.microphone))
                    Spacer()
                    Button("Open Settings", action: viewModel.openMicrophoneSettings)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func permissionIcon(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: return "checkmark.circle"
        case .denied: return "xmark.circle"
        case .notDetermined: return "questionmark.circle"
        }
    }
}

private struct AppIconPickerView: View {
    @ObservedObject var appIconController: AppIconController

    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(CaptureAppIcon.allCases) { icon in
                Button {
                    appIconController.selectedIcon = icon
                } label: {
                    AppIconTile(
                        icon: icon,
                        image: appIconController.previewImage(for: icon),
                        isSelected: appIconController.selectedIcon == icon
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(icon.title) app icon")
                .help("Use \(icon.title) as the Dock icon")
            }
        }
    }
}

private struct AppIconTile: View {
    let icon: CaptureAppIcon
    let image: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                iconImage

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(.black.opacity(0.2)))
                        .offset(x: 5, y: -5)
                }
            }

            Text(icon.title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconImage: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.tertiary)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "app")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct ShortcutRecorderButton: View {
    let action: HotkeyAction
    @ObservedObject var preferences: HotkeyPreferences
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press keys..." : currentLabel) {
            beginRecording()
        }
        .monospacedDigit()
        .help("Click, then press the new shortcut.")
        .onDisappear {
            endRecording()
        }
    }

    private var currentLabel: String {
        preferences.shortcuts[action]?.displayString ?? "Set"
    }

    private func beginRecording() {
        endRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hotkey = Hotkey.from(event: event)
            preferences.set(hotkey, for: action)
            endRecording()
            return nil
        }
    }

    private func endRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
