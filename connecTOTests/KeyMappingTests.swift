import Testing
@testable import connecTO

struct KeyMappingTests {
    @Test func plainLetterStaysText() {
        #expect(KeyMapping.resolve("c", modifiers: []) == .text("c"))
    }

    @Test func commandLetterBecomesTheANSIKey() {
        #expect(KeyMapping.resolve("c", modifiers: .command) == .key(8, .command))
        #expect(KeyMapping.resolve("C", modifiers: .command) == .key(8, .command))
    }

    @Test func aWordWithCommandStaysText() {
        #expect(KeyMapping.resolve("hola", modifiers: .command) == .text("hola"))
    }
}
