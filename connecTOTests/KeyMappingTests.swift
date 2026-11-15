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

    @Test func shiftTypesTheShiftedKey() {
        #expect(KeyMapping.resolve("c", modifiers: .shift) == .key(8, .shift))
        #expect(KeyMapping.resolve("á", modifiers: .shift) == .text("Á"))
    }

    @Test func capsLockActsAsShiftUntilShiftCancelsIt() {
        #expect(KeyMapping.hardwareModifiers(shift: false, capsLock: true, command: false, option: false, control: false) == .shift)
        #expect(KeyMapping.hardwareModifiers(shift: true, capsLock: true, command: false, option: false, control: false) == [])
        #expect(KeyMapping.hardwareModifiers(shift: true, capsLock: false, command: true, option: false, control: false) == [.shift, .command])
    }

    @Test func iPadKeyBecomesTheMacKey() {
        #expect(HardwareKeyCode.macKeyCode(hidUsage: 4) == 0)
        #expect(HardwareKeyCode.macKeyCode(hidUsage: 22) == 1)
        #expect(HardwareKeyCode.macKeyCode(hidUsage: 40) == 36)
        #expect(HardwareKeyCode.macKeyCode(hidUsage: 80) == 123)
        #expect(HardwareKeyCode.macKeyCode(hidUsage: 224) == nil)
    }
}
