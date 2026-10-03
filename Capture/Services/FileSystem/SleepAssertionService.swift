import Foundation
import IOKit.pwr_mgt

protocol SleepPreventing {
    func beginActivity() throws
    func endActivity()
}

final class SleepAssertionService: SleepPreventing {
    private var assertionID: IOPMAssertionID = 0

    func beginActivity() throws {
        guard assertionID == 0 else {
            return
        }

        let reason = "Capture is recording the screen" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
            throw RecorderFailure.captureFailed("Capture could not prevent the Mac from sleeping during recording.")
        }
    }

    func endActivity() {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    deinit {
        endActivity()
    }
}

