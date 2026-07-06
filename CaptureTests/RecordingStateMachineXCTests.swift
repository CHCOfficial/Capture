import Foundation
import XCTest
@testable import Capture

final class RecordingStateMachineXCTests: XCTestCase {
    func testRejectsStoppingFromIdle() {
        var machine = RecordingStateMachine()

        XCTAssertThrowsError(try machine.transition(to: .stopping))
        XCTAssertEqual(machine.state, .idle)
    }
}

