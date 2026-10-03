import Foundation

protocol RecordingFileManaging {
    func defaultRecordingsDirectory() -> URL
    func ensureDirectoryExists(_ directory: URL) throws
    func validateWritableDirectory(_ directory: URL) throws
    func makeUniqueRecordingURL(directory: URL, container: OutputContainer, date: Date) throws -> URL
    func diskSpaceReport(for directory: URL, warningThresholdBytes: Int64) throws -> DiskSpaceReport
    func fileSize(at url: URL) -> Int64
    func cleanupAbandonedTemporaryFiles(in directory: URL) throws
}

actor RecordingFileService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func defaultRecordingsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Capture", isDirectory: true)
    }

    func ensureDirectoryExists(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func validateWritableDirectory(_ directory: URL) throws {
        try ensureDirectoryExists(directory)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RecorderFailure.destinationUnavailable("The selected destination is not a folder.")
        }

        let probeURL = directory.appendingPathComponent(".capture-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try? fileManager.removeItem(at: probeURL)
        } catch {
            throw RecorderFailure.destinationUnavailable("Capture cannot write to \(directory.path).")
        }
    }

    func makeUniqueRecordingURL(directory: URL, container: OutputContainer, date: Date = Date()) throws -> URL {
        try validateWritableDirectory(directory)

        let baseName = "Screen Recording \(Self.filenameDateFormatter.string(from: date))"
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(container.fileExtension)

        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(container.fileExtension)
            suffix += 1
        }

        return candidate
    }

    func diskSpaceReport(for directory: URL, warningThresholdBytes: Int64 = 2_000_000_000) throws -> DiskSpaceReport {
        try ensureDirectoryExists(directory)

        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskSpaceReport(availableBytes: available, isLow: available < warningThresholdBytes)
    }

    func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        if let fileSize = values?.fileSize {
            return Int64(fileSize)
        }
        if let allocated = values?.totalFileAllocatedSize {
            return Int64(allocated)
        }
        return 0
    }

    func cleanupAbandonedTemporaryFiles(in directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls where url.pathExtension == "capturetmp" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}
