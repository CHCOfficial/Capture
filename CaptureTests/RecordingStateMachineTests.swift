import Foundation

#if canImport(Testing)
import Testing
@testable import Capture

@Test func recordingStateMachineAcceptsNormalWorkflow() throws {
    var machine = RecordingStateMachine()
    try machine.transition(to: .preparing)
    try machine.transition(to: .countdown(remaining: 3))
    try machine.transition(to: .countdown(remaining: 2))
    try machine.transition(to: .preparing)
    try machine.transition(to: .recording(startedAt: Date()))

    let startedAt = Date()
    try machine.transition(to: .paused(startedAt: startedAt, pausedAt: Date()))
    try machine.transition(to: .recording(startedAt: startedAt))
    try machine.transition(to: .stopping)
    try machine.transition(to: .finalising)

    let recording = Recording(
        url: URL(fileURLWithPath: "/tmp/test.mp4"),
        createdAt: Date(),
        duration: 1,
        byteCount: 1,
        sourceTitle: "Test"
    )
    try machine.transition(to: .completed(recording))

    #expect(machine.state == .completed(recording))
}

@Test func recordingStateMachineRejectsInvalidPauseFromIdle() {
    var machine = RecordingStateMachine()

    #expect(throws: RecorderFailure.self) {
        try machine.transition(to: .paused(startedAt: Date(), pausedAt: Date()))
    }

    #expect(machine.state == .idle)
}
#endif
