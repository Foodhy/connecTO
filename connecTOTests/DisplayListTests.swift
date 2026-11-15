import Foundation
import Testing
@testable import connecTO

struct DisplayListTests {
    private let studio = SharedDisplay(id: 2, name: "Studio Display", width: 2560, height: 1440)
    private let builtIn = SharedDisplay(id: 1, name: "Built-in", width: 1920, height: 1080)
    private let side = SharedDisplay(id: 3, name: "Side", width: 1920, height: 1080)

    @Test func theMainDisplayComesFirst() {
        let ordered = DisplayList.ordered([studio, side, builtIn], mainID: 1)
        #expect(ordered.map(\.id) == [1, 3, 2])
    }

    @Test func aMissingChoiceFallsBackToTheMainDisplay() {
        let displays = [builtIn, studio]
        #expect(DisplayList.resolvedID(preferred: 99, displays: displays, mainID: 1) == 1)
        #expect(DisplayList.resolvedID(preferred: 2, displays: displays, mainID: 1) == 2)
        #expect(DisplayList.resolvedID(preferred: nil, displays: displays, mainID: 9) == 1)
    }
}
