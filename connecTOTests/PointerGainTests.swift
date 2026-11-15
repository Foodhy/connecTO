import Foundation
import Testing
@testable import connecTO

struct PointerGainTests {
    @Test func stillFingerDoesNotMove() {
        let delta = PointerGain.cursorDelta(dx: 0, dy: 0)
        #expect(delta.dx == 0)
        #expect(delta.dy == 0)
    }

    @Test func knownDistancesUseAnExactGain() {
        #expect(PointerGain.cursorDelta(dx: 20, dy: 0).dx == 40)
        #expect(PointerGain.cursorDelta(dx: 40, dy: 0).dx == 120)
        #expect(PointerGain.cursorDelta(dx: 80, dy: 0).dx == 240)
        #expect(PointerGain.cursorDelta(dx: -20, dy: 0).dx == -40)
    }

    @Test func fasterMovementHasAHigherGain() {
        let slow = abs(PointerGain.cursorDelta(dx: 10, dy: 0).dx) / 10
        let fast = abs(PointerGain.cursorDelta(dx: 40, dy: 0).dx) / 40
        #expect(fast > slow)
    }

    @Test func directionIsPreserved() {
        let delta = PointerGain.cursorDelta(dx: -20, dy: 20)
        #expect(delta.dx < 0)
        #expect(delta.dy > 0)
    }
}
