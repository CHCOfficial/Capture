import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var viewModel: RecorderViewModel?
    private var floatingController: FloatingControllerWindowController?
    private var statusController: StatusItemController?
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
