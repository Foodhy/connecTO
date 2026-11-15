import Foundation

/// Control y una flecha, en el orden que Mission Control entiende.
/// La flecha sale con Control pulsado: si no, YouTube la toma como flecha sola.
nonisolated enum SpaceChord {
    static let controlKey: UInt16 = 0x3B

    struct Step: Equatable, Sendable {
        var keyCode: UInt16
        var down: Bool
        var control: Bool
    }

    static func steps(arrow: UInt16) -> [Step] {
        [
            Step(keyCode: controlKey, down: true, control: true),
            Step(keyCode: arrow, down: true, control: true),
            Step(keyCode: arrow, down: false, control: true),
            Step(keyCode: controlKey, down: false, control: false),
        ]
    }

    static func isDesktopArrow(_ code: UInt16) -> Bool {
        code == SpecialKey.left || code == SpecialKey.right || code == SpecialKey.up || code == SpecialKey.down
    }

    /// Primera pulsación: Control y flecha arriba. La siguiente: Control y flecha abajo.
    static func windowsArrow(alreadyOpen: Bool) -> UInt16 {
        alreadyOpen ? SpecialKey.down : SpecialKey.up
    }
}
