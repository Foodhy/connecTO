import Testing
@testable import connecTO

struct SpaceChordTests {
    @Test func arrowKeepsControlHeld() {
        for arrow in [SpecialKey.left, SpecialKey.right, SpecialKey.up, SpecialKey.down] {
            let steps = SpaceChord.steps(arrow: arrow)
            #expect(steps.map(\.keyCode) == [
                SpaceChord.controlKey,
                arrow,
                arrow,
                SpaceChord.controlKey,
            ])
            #expect(steps.map(\.down) == [true, true, false, false])
            #expect(steps[1].control)
            #expect(steps[2].control)
            #expect(!steps[3].control)
        }
    }

    @Test func windowsOpensUpThenClosesDown() {
        #expect(SpaceChord.windowsArrow(alreadyOpen: false) == SpecialKey.up)
        #expect(SpaceChord.windowsArrow(alreadyOpen: true) == SpecialKey.down)
    }
}
