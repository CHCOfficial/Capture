import AppKit
import Foundation
import ScreenCaptureKit

@MainActor
final class ShareableContentProvider: ObservableObject {
    @Published private(set) var displays: [CaptureSource] = []
    @Published private(set) var windows: [CaptureSource] = []
    @Published private(set) var applications: [CaptureSource] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private var displayReferences: [CaptureSource.ID: SCDisplay] = [:]
    private var windowReferences: [CaptureSource.ID: SCWindow] = [:]
    private var applicationReferences: [CaptureSource.ID: SCRunningApplication] = [:]
    private var currentApplication: SCRunningApplication?
    private var latestContent: SCShareableContent?

    func refresh() async {
        guard SystemCompatibility.isSupported else {
            errorMessage = SystemCompatibility.unsupportedMessage
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let content = try await SCShareableContent.current
            latestContent = content
            rebuildSources(from: content)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func source(for selection: CaptureSelection) -> CaptureSource? {
        switch selection.mode {
        case .display, .region:
            return displays.first { $0.id == selection.sourceID } ?? displays.first
        case .window:
            return windows.first { $0.id == selection.sourceID } ?? windows.first
        case .application:
            return applications.first { $0.id == selection.sourceID } ?? applications.first
        }
    }

    func resolvedTarget(for selection: CaptureSelection, configuration: RecordingConfiguration) throws -> ResolvedCaptureTarget {
        switch selection.mode {
        case .display:
            guard let source = source(for: selection), let display = displayReferences[source.id] else {
                throw RecorderFailure.noCaptureSource
            }
            return .display(display, excludedApplications: excludedApplications(configuration: configuration), region: nil)
        case .region:
            guard let source = source(for: selection), let display = displayReferences[source.id] else {
                throw RecorderFailure.noCaptureSource
            }
            let region = selection.region ?? defaultRegion(in: source.frame)
            return .display(display, excludedApplications: excludedApplications(configuration: configuration), region: region)
        case .window:
            guard let source = source(for: selection), let window = windowReferences[source.id] else {
                throw RecorderFailure.noCaptureSource
            }
            return .window(window)
        case .application:
            guard let source = source(for: selection),
                  let application = applicationReferences[source.id],
                  let display = displayForApplication(application) else {
                throw RecorderFailure.noCaptureSource
            }
            return .application(application, display: display, excludedWindows: [])
        }
    }

    func allSources(for mode: CaptureMode) -> [CaptureSource] {
        switch mode {
        case .display, .region: return displays
        case .window: return windows
        case .application: return applications
        }
    }

    private func rebuildSources(from content: SCShareableContent) {
        displayReferences.removeAll()
        windowReferences.removeAll()
        applicationReferences.removeAll()
        currentApplication = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }

        displays = content.displays
            .sorted { $0.displayID < $1.displayID }
            .enumerated()
            .map { index, display in
                let id = "display-\(display.displayID)"
                displayReferences[id] = display
                return CaptureSource(
                    id: id,
                    kind: .display,
                    title: displayTitle(for: display, index: index),
                    subtitle: "\(display.width)x\(display.height) pt",
                    displayID: display.displayID,
                    windowID: nil,
                    processID: nil,
                    bundleIdentifier: nil,
                    frame: display.frame
                )
            }

        windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0 && window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
            }
            .sorted { left, right in
                let leftName = left.owningApplication?.applicationName ?? ""
                let rightName = right.owningApplication?.applicationName ?? ""
                if leftName == rightName {
                    return (left.title ?? "") < (right.title ?? "")
                }
                return leftName < rightName
            }
            .prefix(120)
            .map { window in
                let id = "window-\(window.windowID)"
                windowReferences[id] = window
                let appName = window.owningApplication?.applicationName ?? "Unknown App"
                return CaptureSource(
                    id: id,
                    kind: .window,
                    title: window.title?.isEmpty == false ? window.title! : appName,
                    subtitle: appName,
                    displayID: nil,
                    windowID: window.windowID,
                    processID: window.owningApplication?.processID,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier,
                    frame: window.frame
                )
            }

        applications = content.applications
            .filter { application in
                application.processID != ProcessInfo.processInfo.processIdentifier
            }
            .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
            .map { application in
                let id = "app-\(application.processID)"
                applicationReferences[id] = application
                return CaptureSource(
                    id: id,
                    kind: .application,
                    title: application.applicationName,
                    subtitle: application.bundleIdentifier,
                    displayID: nil,
                    windowID: nil,
                    processID: application.processID,
                    bundleIdentifier: application.bundleIdentifier,
                    frame: .zero
                )
            }
    }

    private func displayTitle(for display: SCDisplay, index: Int) -> String {
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == display.displayID
        }

        if screen == NSScreen.main {
            return "Main Display"
        }

        return "Display \(index + 1)"
    }

    private func excludedApplications(configuration: RecordingConfiguration) -> [SCRunningApplication] {
        guard !configuration.includeCaptureAppInDisplayRecordings else {
            return []
        }

        return currentApplication.map { [$0] } ?? []
    }

    private func displayForApplication(_ application: SCRunningApplication) -> SCDisplay? {
        guard let content = latestContent else {
            return displays.first.flatMap { displayReferences[$0.id] }
        }

        let appWindows = content.windows.filter { $0.owningApplication?.processID == application.processID }
        if let matchingDisplay = content.displays.first(where: { display in
            appWindows.contains { window in
                display.frame.intersects(window.frame)
            }
        }) {
            return matchingDisplay
        }

        return content.displays.first
    }

    private func defaultRegion(in displayFrame: CGRect) -> CGRect {
        let width = max(640, displayFrame.width * 0.55)
        let height = max(360, displayFrame.height * 0.55)
        return CGRect(
            x: displayFrame.midX - width / 2,
            y: displayFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

enum ResolvedCaptureTarget {
    case display(SCDisplay, excludedApplications: [SCRunningApplication], region: CGRect?)
    case window(SCWindow)
    case application(SCRunningApplication, display: SCDisplay, excludedWindows: [SCWindow])

    var sourceRect: CGRect {
        switch self {
        case .display(let display, _, let region):
            return region ?? display.frame
        case .window(let window):
            return window.frame
        case .application(_, let display, _):
            return display.frame
        }
    }

    var defaultTitle: String {
        switch self {
        case .display(_, _, let region):
            return region == nil ? "Display" : "Region"
        case .window(let window):
            return window.title ?? window.owningApplication?.applicationName ?? "Window"
        case .application(let application, _, _):
            return application.applicationName
        }
    }
}
