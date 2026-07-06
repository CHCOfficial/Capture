import SwiftUI

enum CaptureLinks {
    static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/chcofficial")!
}

@main
struct CaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = RecorderViewModel()
    @StateObject private var appIconController = AppIconController()

    var body: some Scene {
        WindowGroup {
            RecorderView(viewModel: viewModel, appIconController: appIconController)
                .frame(minWidth: 760, minHeight: 560)
                .task {
                    appDelegate.configure(with: viewModel)
                    appIconController.applySelectedIcon()
                    await viewModel.refreshAll()
                }
                .onChange(of: viewModel.configuration.showsStatusItem) { _, newValue in
                    appDelegate.setStatusItemVisible(newValue)
                }
                .onChange(of: viewModel.hotkeyPreferences.shortcuts) { _, shortcuts in
                    appDelegate.restartHotkeys(shortcuts: shortcuts)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Capture") {
                    appDelegate.showAboutPanel()
                }
            }

            CommandMenu("Recording") {
                Button(viewModel.state.isActive ? "Stop Recording" : "Start Recording") {
                    viewModel.state.isActive ? viewModel.stop() : viewModel.start()
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Pause / Resume") {
                    viewModel.pauseOrResume()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!viewModel.state.isActive)

                Button("Cancel Countdown") {
                    viewModel.cancelCountdown()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }

        Settings {
            SettingsView(viewModel: viewModel, appIconController: appIconController)
                .frame(width: 520)
        }
    }
}
