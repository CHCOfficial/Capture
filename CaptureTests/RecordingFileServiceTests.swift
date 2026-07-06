import Foundation
import XCTest
@testable import Capture

final class RecordingFileServiceTests: XCTestCase {
    func testUniqueRecordingURLDoesNotOverwriteExistingFile() async throws {
        let service = RecordingFileService()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureFileServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let date = Date(timeIntervalSince1970: 1_771_482_138)
        let firstURL = try await service.makeUniqueRecordingURL(directory: directory, container: .mp4, date: date)
        try Data("existing".utf8).write(to: firstURL)

        let secondURL = try await service.makeUniqueRecordingURL(directory: directory, container: .mp4, date: date)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testDefaultDirectoryIsMoviesCapture() async {
        let service = RecordingFileService()
        let directory = await service.defaultRecordingsDirectory()

        XCTAssertEqual(directory.lastPathComponent, "Capture")
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "Movies")
    }
}

