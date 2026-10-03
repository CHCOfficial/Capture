import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var viewModel: RecorderViewModel?
    private var floatingController: FloatingControllerWindowController?
    private var statusController: StatusItemController?
    private var aboutWindow: NSWindow?
    private let hotkeyCenter = HotkeyCenter()
    private var hasConfigured = false

    func configure(with viewModel: RecorderViewModel) {
        guard !hasConfigured else {
            return
        }

        hasConfigured = true
        self.viewModel = viewModel
        floatingController = FloatingControllerWindowController(viewModel: viewModel)
        statusController = StatusItemController(viewModel: viewModel)

        viewModel.onShowFloatingController = { [weak self] in
            self?.floatingController?.show()
        }
        viewModel.onHideFloatingController = { [weak self] in
            self?.floatingController?.hide()
        }
        viewModel.onHideMainWindow = {
            NSApp.keyWindow?.orderOut(nil)
        }
        viewModel.onShowMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
            self.normalizeMainWindowChrome()
        }
        viewModel.onStatusItemVisibilityChanged = { [weak self] visible in
            self?.setStatusItemVisible(visible)
        }

        restartHotkeys(shortcuts: viewModel.hotkeyPreferences.shortcuts)
        setStatusItemVisible(viewModel.configuration.showsStatusItem)
        Task { @MainActor in
            normalizeMainWindowChrome()
        }
    }

    func restartHotkeys(shortcuts: [HotkeyAction: Hotkey]) {
        guard let viewModel else {
            return
        }
        hotkeyCenter.start(shortcuts: shortcuts) { [weak viewModel] action in
            viewModel?.handleHotkey(action)
        }
    }

    func setStatusItemVisible(_ visible: Bool) {
        statusController?.isVisible = visible
    }

    func showAboutPanel() {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = NSHostingView(rootView: AboutCaptureView())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Capture"
        panel.contentView = contentView
        panel.isReleasedWhenClosed = false
        panel.center()

        aboutWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        normalizeMainWindowChrome()
        Task { [weak viewModel] in
            await viewModel?.refreshPermissionsAndContent()
            viewModel?.beginPermissionRefreshPolling()
        }
    }

    private func normalizeMainWindowChrome() {
        for window in NSApp.windows where !(window is NSPanel) {
            window.title = "Capture"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.styleMask.remove(.fullSizeContentView)
            window.isMovableByWindowBackground = false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel?.state.isActive == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Stop the active recording?"
        alert.informativeText = "Capture needs to finalise the file before quitting."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Recording")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel?.stop()
        }
        return .terminateCancel
    }
}

private struct AboutCaptureView: View {
    var body: some View {
        VStack(spacing: 18) {
            appIcon

            VStack(spacing: 4) {
                Text("Capture")
                    .font(.system(.title2, weight: .semibold))
                Text(versionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A native macOS screen recorder for clean captures, fast setup, and calm day-to-day recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(CaptureLinks.buyMeACoffeeURL)
            } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.purple)
            .help("Open Buy Me a Coffee")

            Text(CaptureLinks.buyMeACoffeeURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            Text("Use, adapt, and share Capture with appropriate credit and this support link retained.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .frame(width: 420)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                .accessibilityHidden(true)
        }
    }

    private var versionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let build, !build.isEmpty {
            return "Version \(version) (\(build))"
        }

        return "Version \(version)"
    }
}
