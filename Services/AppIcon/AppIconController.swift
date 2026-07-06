import AppKit
import Foundation

enum CaptureAppIcon: String, CaseIterable, Identifiable, Codable {
    case lens
    case focus
    case snapshot
    case shutter
    case frame
    case monogram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lens: return "Lens"
        case .focus: return "Focus"
        case .snapshot: return "Snapshot"
        case .shutter: return "Shutter"
        case .frame: return "Frame"
        case .monogram: return "Monogram"
        }
    }

    var resourceBaseName: String {
        switch self {
        case .lens: return "Capture-Lens"
        case .focus: return "Capture-Focus"
        case .snapshot: return "Capture-Snapshot"
        case .shutter: return "Capture-Shutter"
        case .frame: return "Capture-Frame"
        case .monogram: return "Capture-Monogram"
        }
    }

    var previewFileName: String {
        "\(resourceBaseName)-512"
    }
}

@MainActor
final class AppIconController: ObservableObject {
    @Published var selectedIcon: CaptureAppIcon {
        didSet {
            save()
            applySelectedIcon()
        }
    }

    private let defaults: UserDefaults
    private let defaultsKey = "Capture.selectedAppIcon"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: defaultsKey),
           let icon = CaptureAppIcon(rawValue: rawValue) {
            selectedIcon = icon
        } else {
            selectedIcon = .lens
        }
    }

    func applySelectedIcon() {
        guard let image = roundedIconImage(for: selectedIcon, pointSize: 1024) else {
            return
        }
        NSApp.applicationIconImage = image
    }

    func iconImage(for icon: CaptureAppIcon) -> NSImage? {
        guard let url = resourceURL(for: icon.resourceBaseName, extension: "icns") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    func previewImage(for icon: CaptureAppIcon) -> NSImage? {
        guard let url = resourceURL(for: icon.previewFileName, extension: "png") else {
            return roundedIconImage(for: icon, pointSize: 512)
        }

        return roundedImage(from: NSImage(contentsOf: url), pointSize: 512)
    }

    func roundedIconImage(for icon: CaptureAppIcon, pointSize: CGFloat) -> NSImage? {
        roundedImage(from: iconImage(for: icon), pointSize: pointSize)
    }

    private func resourceURL(for name: String, extension fileExtension: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "AppIcons")
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "IconChoices")
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
    }

    private func roundedImage(from sourceImage: NSImage?, pointSize: CGFloat) -> NSImage? {
        guard let sourceImage else {
            return nil
        }

        let size = NSSize(width: pointSize, height: pointSize)
        let targetImage = NSImage(size: size)
        targetImage.lockFocus()
        defer { targetImage.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let rect = NSRect(origin: .zero, size: size)
        let radius = pointSize * 0.2237
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()

        sourceImage.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        targetImage.isTemplate = false
        return targetImage
    }

    private func save() {
        defaults.set(selectedIcon.rawValue, forKey: defaultsKey)
    }
}
