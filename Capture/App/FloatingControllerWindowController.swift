import AppKit
import SwiftUI

@MainActor
final class FloatingControllerWindowController: NSObject, NSWindowDelegate {
    private let viewModel: RecorderViewModel
    private let window: NSPanel
    private let frameKey = "Capture.floatingControllerFrame"

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        let contentView = FloatingControllerView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 58),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init()
        window.delegate = self
        restoreFrame()
    }

    func show() {
        restoreFrame()
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    private func restoreFrame() {
        if let saved = UserDefaults.standard.string(forKey: frameKey) {
            let rect = NSRectFromString(saved)
            if !rect.isEmpty {
                window.setFrame(rect, display: false)
                return
            }
        }

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screenFrame.midX - 155, y: screenFrame.maxY - 92)
            window.setFrameOrigin(origin)
        }
    }
}

