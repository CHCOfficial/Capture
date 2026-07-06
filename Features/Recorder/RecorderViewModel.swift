import AppKit
import AVFoundation
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var selection = CaptureSelection() {
        didSet {
            if oldValue != selection {
                Task { await refreshPreview() }
            }
        }
    }

    @Published var configuration = RecordingConfiguration() {
        didSet {
            if oldValue != configuration {
                Task { await refreshPreview() }
                updateMicrophoneMeter()
            }
        }
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var permissions = CapturePermissionSnapshot(screenRecording: .notDetermined, microphone: .notDetermined)
    @Published private(set) var microphones: [MicrophoneDevice] = []
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var recentRecordings: [Recording] = []
    @Published private(set) var diskSpaceReport: DiskSpaceReport?
    @Published var outputDirectory: URL
    @Published var alertMessage: String?
    @Published var renameDraft = ""

    let sourceProvider: ShareableContentProvider
    let previewController: PreviewCaptureController
    let microphoneLevelMeter: MicrophoneLevelMeter
    let hotkeyPreferences: HotkeyPreferences

    var onShowFloatingController: (() -> Void)?
    var onHideFloatingController: (() -> Void)?
    var onHideMainWindow: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var onStatusItemVisibilityChanged: ((Bool) -> Void)?

    private let permissionService: PermissionAuthorizing
    private let microphoneProvider: MicrophoneProviding
    private let fileService: RecordingFileService
    private let sleepAssertion: SleepPreventing
    private var stateMachine = RecordingStateMachine()
    private var captureSession: ScreenCaptureSession?
    private var recordingTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var permissionRefreshTask: Task<Void, Never>?
    private var currentOutputURL: URL?
    private var recordingStartedAt: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var pauseBeganAt: Date?

    init(
        permissionService: PermissionAuthorizing = SystemPermissionService(),
        microphoneProvider: MicrophoneProviding = SystemMicrophoneProvider(),
        fileService: RecordingFileService = RecordingFileService(),
        sleepAssertion: SleepPreventing = SleepAssertionService(),
        sourceProvider: ShareableContentProvider? = nil,
        previewController: PreviewCaptureController? = nil,
        microphoneLevelMeter: MicrophoneLevelMeter? = nil,
        hotkeyPreferences: HotkeyPreferences? = nil
    ) {
        self.permissionService = permissionService
        self.microphoneProvider = microphoneProvider
        self.fileService = fileService
        self.sleepAssertion = sleepAssertion
        self.sourceProvider = sourceProvider ?? ShareableContentProvider()
        self.previewController = previewController ?? PreviewCaptureController()
        self.microphoneLevelMeter = microphoneLevelMeter ?? MicrophoneLevelMeter()
        self.hotkeyPreferences = hotkeyPreferences ?? HotkeyPreferences()
        self.outputDirectory = fileService.defaultRecordingsDirectory()
    }

    func start() {
        guard !state.isActive else {
            return
        }

        recordingTask = Task {
            await startRecordingFlow()
        }
    }

    func pauseOrResume() {
        switch state {
        case .recording(let startedAt):
            captureSession?.pause()
            pauseBeganAt = Date()
            transition(to: .paused(startedAt: startedAt, pausedAt: pauseBeganAt ?? Date()))
        case .paused(let startedAt, _):
            if let pauseBeganAt {
                accumulatedPausedTime += Date().timeIntervalSince(pauseBeganAt)
            }
            self.pauseBeganAt = nil
            captureSession?.resume()
            transition(to: .recording(startedAt: startedAt))
        default:
            break
        }
    }

    func stop() {
        guard state.isActive else {
            return
        }

        if case .countdown = state {
            cancelCountdown()
            return
        }

        Task {
            await stopRecordingFlow()
        }
    }

    func cancelCountdown() {
        guard case .countdown = state else {
            return
        }
        recordingTask?.cancel()
        recordingTask = nil
        transition(to: .idle)
        elapsedTime = 0
        onShowMainWindow?()
        Task { await refreshPreview() }
    }

    func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .startStop:
            state.isActive ? stop() : start()
        case .pauseResume:
            pauseOrResume()
        case .cancelCountdown:
            cancelCountdown()
        }
    }

    func refreshAll() async {
        await refreshPermissionsAndContent()
        microphones = microphoneProvider.availableMicrophones()
        await refreshDiskSpace()
        await loadRecentRecordings()
        await cleanupAbandonedTemporaryFiles()
        updateMicrophoneMeter()
        onStatusItemVisibilityChanged?(configuration.showsStatusItem)
    }

    func refreshPermissions() {
        applyPermissionSnapshot(permissionService.snapshot())
    }

    func refreshPermissionsAndContent() async {
        applyPermissionSnapshot(await permissionService.refreshedSnapshot())

        if permissions.screenRecording == .granted {
            await sourceProvider.refresh()
            selectDefaultSourceIfNeeded()
            await refreshPreview()
        } else {
            await previewController.stop()
        }
    }

    func beginPermissionRefreshPolling() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { [weak self] in
            for _ in 0..<12 {
                guard !Task.isCancelled else {
                    return
                }

                await self?.refreshPermissionsAndContent()
                if self?.permissions.screenRecording == .granted {
                    return
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func requestScreenPermission() {
        Task {
            transition(to: .requestingPermission)
            let granted = await permissionService.requestScreenRecordingAccess()
            await refreshPermissionsAndContent()
            let isGranted = granted || permissions.screenRecording == .granted
            transition(to: isGranted ? .idle : .failed(.missingScreenRecordingPermission))
            beginPermissionRefreshPolling()
        }
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await permissionService.requestMicrophoneAccess()
            await refreshPermissionsAndContent()
            if !granted {
                alertMessage = RecorderFailure.missingMicrophonePermission.localizedDescription
            }
        }
    }

    func openScreenRecordingSettings() {
        permissionService.openScreenRecordingSettings()
        beginPermissionRefreshPolling()
    }

    func openMicrophoneSettings() {
        permissionService.openMicrophoneSettings()
        beginPermissionRefreshPolling()
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            Task {
                await refreshDiskSpace()
                await loadRecentRecordings()
            }
        }
    }

    func revealInFinder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func preview(_ recording: Recording) {
        NSWorkspace.shared.open(recording.url)
    }

    func copyPath(_ recording: Recording) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recording.url.path, forType: .string)
    }

    func share(_ recording: Recording) {
        guard let view = NSApp.keyWindow?.contentView else {
            return
        }
        let picker = NSSharingServicePicker(items: [recording.url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func delete(_ recording: Recording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            recentRecordings.removeAll { $0.id == recording.id }
            transition(to: .idle)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func rename(_ recording: Recording, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let destination = recording.url
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .appendingPathExtension(recording.url.pathExtension)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            alertMessage = "A recording with that name already exists."
            return
        }

        do {
            try FileManager.default.moveItem(at: recording.url, to: destination)
            if let index = recentRecordings.firstIndex(of: recording) {
                recentRecordings[index].url = destination
            }
            if case .completed(let completedRecording) = state, completedRecording == recording {
                var updated = completedRecording
                updated.url = destination
                transition(to: .completed(updated))
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func selectDefaultSourceIfNeeded() {
        let availableSources = sourceProvider.allSources(for: selection.mode)
        if selection.sourceID == nil || !availableSources.contains(where: { $0.id == selection.sourceID }) {
            selection.sourceID = availableSources.first?.id
        }
    }

    func refreshPreview() async {
        guard permissions.screenRecording == .granted,
              !state.isActive,
              let target = try? sourceProvider.resolvedTarget(for: selection, configuration: configuration) else {
            await previewController.stop()
            return
        }

        await previewController.start(target: target, configuration: configuration)
    }

    func refreshDiskSpace() async {
        do {
            diskSpaceReport = try await fileService.diskSpaceReport(for: outputDirectory, warningThresholdBytes: 2_000_000_000)
        } catch {
            diskSpaceReport = nil
        }
    }

    func loadRecentRecordingsForUI() async {
        await loadRecentRecordings()
    }

    var elapsedText: String {
        Self.timeFormatter.string(from: elapsedTime) ?? "00:00"
    }

    var primaryButtonTitle: String {
        switch state {
        case .idle, .completed, .failed:
            return "Record"
        case .countdown:
            return "Cancel"
        case .recording, .paused, .stopping, .finalising, .preparing, .requestingPermission:
            return "Stop"
        }
    }

    var canRecord: Bool {
        switch state {
        case .idle, .completed, .failed:
            return permissions.screenRecording == .granted && sourceProvider.source(for: selection) != nil
        default:
            return false
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            return permissions.screenRecording == .granted ? "Ready" : "Screen Recording permission needed"
        case .requestingPermission:
            return "Requesting permission..."
        case .preparing:
            return "Preparing..."
        case .countdown(let remaining):
            return remaining > 0 ? "Recording starts in \(remaining)" : "Starting..."
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping..."
        case .finalising:
            return "Finalising..."
        case .completed:
            return "Saved"
        case .failed(let failure):
            return failure.localizedDescription
        }
    }

    private func startRecordingFlow() async {
        defer {
            recordingTask = nil
        }

        do {
            try validateSystemSupport()
            try await ensurePermissions()
            transition(to: .preparing)

            await previewController.stop()
            await refreshDiskSpace()

            if let diskSpaceReport, diskSpaceReport.availableBytes < 250_000_000 {
                throw RecorderFailure.lowDiskSpace(availableBytes: diskSpaceReport.availableBytes)
            }

            try await fileService.validateWritableDirectory(outputDirectory)
            let outputURL = try await fileService.makeUniqueRecordingURL(
                directory: outputDirectory,
                container: configuration.outputContainer,
                date: Date()
            )
            currentOutputURL = outputURL

            let target = try sourceProvider.resolvedTarget(for: selection, configuration: configuration)
            if configuration.hidesMainWindowDuringCapture {
                onHideMainWindow?()
            }

            if configuration.countdown.rawValue > 0 {
                try await runCountdown(seconds: configuration.countdown.rawValue)
            }

            transition(to: .preparing)
            try sleepAssertion.beginActivity()

            let session = ScreenCaptureSession()
            session.onFailure = { [weak self] failure in
                Task { @MainActor in
                    self?.fail(failure)
                }
            }
            session.onSourceBecameUnavailable = { [weak self] in
                Task { @MainActor in
                    self?.fail(.sourceUnavailable("The selected source is no longer available."))
                }
            }
            captureSession = session
            _ = try await session.start(target: target, outputURL: outputURL, configuration: configuration)

            recordingStartedAt = Date()
            accumulatedPausedTime = 0
            pauseBeganAt = nil
            elapsedTime = 0
            transition(to: .recording(startedAt: recordingStartedAt ?? Date()))
            startElapsedTimer()
            onShowFloatingController?()
        } catch is CancellationError {
            transition(to: .idle)
            onShowMainWindow?()
        } catch let failure as RecorderFailure {
            fail(failure)
        } catch {
            fail(.captureFailed(error.localizedDescription))
        }
    }

    private func stopRecordingFlow() async {
        do {
            transition(to: .stopping)
            elapsedTask?.cancel()
            transition(to: .finalising)
            let duration = try await captureSession?.stop() ?? elapsedTime
            captureSession = nil
            sleepAssertion.endActivity()
            onHideFloatingController?()
            onShowMainWindow?()

            guard let url = currentOutputURL else {
                transition(to: .idle)
                return
            }

            let recording = Recording(
                url: url,
                createdAt: Date(),
                duration: duration,
                byteCount: await fileService.fileSize(at: url),
                sourceTitle: sourceProvider.source(for: selection)?.title ?? "Screen"
            )
            recentRecordings.removeAll { $0.url == recording.url }
            recentRecordings.insert(recording, at: 0)
            recentRecordings = Array(recentRecordings.prefix(8))
            transition(to: .completed(recording))
            currentOutputURL = nil
            await refreshPreview()
        } catch let failure as RecorderFailure {
            fail(failure)
        } catch {
            fail(.captureFailed(error.localizedDescription))
        }
    }

    private func ensurePermissions() async throws {
        await refreshPermissionsAndContent()

        if permissions.screenRecording != .granted {
            transition(to: .requestingPermission)
            let granted = await permissionService.requestScreenRecordingAccess()
            await refreshPermissionsAndContent()
            beginPermissionRefreshPolling()
            guard granted || permissions.screenRecording == .granted else {
                throw RecorderFailure.missingScreenRecordingPermission
            }
        }

        if configuration.audioMode.capturesMicrophone && permissions.microphone != .granted {
            transition(to: .requestingPermission)
            let granted = await permissionService.requestMicrophoneAccess()
            await refreshPermissionsAndContent()
            guard granted || permissions.microphone == .granted else {
                throw RecorderFailure.missingMicrophonePermission
            }
        }
    }

    private func runCountdown(seconds: Int) async throws {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            transition(to: .countdown(remaining: remaining))
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        transition(to: .countdown(remaining: 0))
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.updateElapsedTime()
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func updateElapsedTime() {
        guard let recordingStartedAt else {
            elapsedTime = 0
            return
        }

        let now = Date()
        var paused = accumulatedPausedTime
        if let pauseBeganAt {
            paused += now.timeIntervalSince(pauseBeganAt)
        }
        elapsedTime = max(0, now.timeIntervalSince(recordingStartedAt) - paused)
    }

    private func fail(_ failure: RecorderFailure) {
        recordingTask?.cancel()
        elapsedTask?.cancel()
        captureSession?.cancel()
        captureSession = nil
        currentOutputURL = nil
        sleepAssertion.endActivity()
        microphoneLevelMeter.stop()
        onHideFloatingController?()
        onShowMainWindow?()
        transition(to: .failed(failure))
        alertMessage = failure.localizedDescription
        Task { await refreshPreview() }
    }

    private func validateSystemSupport() throws {
        guard SystemCompatibility.isSupported else {
            throw RecorderFailure.unsupportedSystem(SystemCompatibility.unsupportedMessage)
        }
    }

    private func updateMicrophoneMeter() {
        guard configuration.audioMode.capturesMicrophone else {
            microphoneLevelMeter.stop()
            return
        }
        microphoneLevelMeter.start(deviceID: configuration.selectedMicrophoneID)
    }

    private func transition(to newState: RecordingState) {
        do {
            try stateMachine.transition(to: newState)
            state = stateMachine.state
        } catch {
            state = newState
        }
    }

    private func applyPermissionSnapshot(_ snapshot: CapturePermissionSnapshot) {
        permissions = snapshot

        if snapshot.screenRecording == .granted, case .failed(.missingScreenRecordingPermission) = state {
            transition(to: .idle)
        }

        if snapshot.microphone == .granted, case .failed(.missingMicrophonePermission) = state {
            transition(to: .idle)
        }
    }

    private func loadRecentRecordings() async {
        recentRecordings = recentFiles(in: outputDirectory).prefix(8).map { url in
            Recording(
                url: url,
                createdAt: ((try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()),
                duration: 0,
                byteCount: fileSize(url),
                sourceTitle: "Screen"
            )
        }
    }

    private func cleanupAbandonedTemporaryFiles() async {
        try? await fileService.cleanupAbandonedTemporaryFiles(in: outputDirectory)
    }

    private func recentFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
