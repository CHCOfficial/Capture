import AppKit
import Foundation

enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case startStop
    case pauseResume
    case cancelCountdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startStop: return "Start / Stop"
        case .pauseResume: return "Pause / Resume"
        case .cancelCountdown: return "Cancel Countdown"
        }
    }
}

struct Hotkey: Equatable, Codable {
    var keyCode: UInt16
    var modifiersRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && eventModifiers == modifiers.intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "-")
    }

    static let defaultShortcuts: [HotkeyAction: Hotkey] = [
        .startStop: Hotkey(keyCode: 19, modifiersRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue),
        .pauseResume: Hotkey(keyCode: 35, modifiersRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue),
        .cancelCountdown: Hotkey(keyCode: 53, modifiersRawValue: 0)
    ]

    static func from(event: NSEvent) -> Hotkey {
        Hotkey(
            keyCode: event.keyCode,
            modifiersRawValue: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        )
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 53: return "Escape"
        default: return "Key \(keyCode)"
        }
    }
}

@MainActor
final class HotkeyPreferences: ObservableObject {
    @Published var shortcuts: [HotkeyAction: Hotkey] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "Capture.hotkeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HotkeyAction: Hotkey].self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = Hotkey.defaultShortcuts
        }
    }

    func set(_ hotkey: Hotkey, for action: HotkeyAction) {
        shortcuts[action] = hotkey
    }

    func reset() {
        shortcuts = Hotkey.defaultShortcuts
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class HotkeyCenter {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(shortcuts: [HotkeyAction: Hotkey], handler: @escaping (HotkeyAction) -> Void) {
        stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let action = shortcuts.first(where: { $0.value.matches(event) })?.key {
                handler(action)
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if let action = shortcuts.first(where: { $0.value.matches(event) })?.key {
                Task { @MainActor in
                    handler(action)
                }
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }
}
