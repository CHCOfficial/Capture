import Foundation

enum RecordingState: Equatable {
    case idle
    case requestingPermission
    case preparing
    case countdown(remaining: Int)
    case recording(startedAt: Date)
    case paused(startedAt: Date, pausedAt: Date)
    case stopping
    case finalising
    case completed(Recording)
    case failed(RecorderFailure)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .requestingPermission: return "Requesting Permission"
        case .preparing: return "Preparing"
        case .countdown: return "Countdown"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .stopping: return "Stopping"
        case .finalising: return "Finalising"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .countdown, .recording, .paused, .stopping, .finalising:
            return true
        case .idle, .requestingPermission, .preparing, .completed, .failed:
            return false
        }
    }

    var allowsConfigurationChanges: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        default:
            return false
        }
    }
}

struct RecordingStateMachine {
    private(set) var state: RecordingState = .idle

    mutating func reset() {
        state = .idle
    }

    mutating func transition(to next: RecordingState) throws {
        guard canTransition(from: state, to: next) else {
            throw RecorderFailure.invalidTransition(from: state.label, to: next.label)
        }
        state = next
    }

    func canTransition(from current: RecordingState, to next: RecordingState) -> Bool {
        switch (current, next) {
        case (.idle, .requestingPermission),
             (.idle, .preparing),
             (.idle, .failed):
            return true
        case (.requestingPermission, .preparing),
             (.requestingPermission, .idle),
             (.requestingPermission, .failed):
            return true
        case (.preparing, .countdown),
             (.preparing, .recording),
             (.preparing, .failed),
             (.preparing, .idle):
            return true
        case (.countdown, .countdown),
             (.countdown, .preparing),
             (.countdown, .recording),
             (.countdown, .idle),
             (.countdown, .failed):
            return true
        case (.recording, .paused),
             (.recording, .stopping),
             (.recording, .failed):
            return true
        case (.paused, .recording),
             (.paused, .stopping),
             (.paused, .failed):
            return true
        case (.stopping, .finalising),
             (.stopping, .completed),
             (.stopping, .failed):
            return true
        case (.finalising, .completed),
             (.finalising, .failed):
            return true
        case (.completed, .idle),
             (.completed, .preparing):
            return true
        case (.failed, .idle),
             (.failed, .preparing):
            return true
        default:
            return false
        }
    }
}
