import AppKit

@MainActor
final class StatusItemController {
    private weak var viewModel: RecorderViewModel?
    private var statusItem: NSStatusItem?

    var isVisible: Bool = false {
        didSet { updateVisibility() }
    }

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    private func updateVisibility() {
        if isVisible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Capture")
            item.button?.imagePosition = .imageLeading
            item.menu = makeMenu()
            statusItem = item
        } else if !isVisible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Capture", action: #selector(showCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start / Stop Recording", action: #selector(startStop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pause / Resume", action: #selector(pauseResume), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Capture", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func showCapture() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }

    @objc private func startStop() {
        guard let viewModel else {
            return
        }
        viewModel.state.isActive ? viewModel.stop() : viewModel.start()
    }

    @objc private func pauseResume() {
        viewModel?.pauseOrResume()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
