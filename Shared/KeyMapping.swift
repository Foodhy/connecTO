import Foundation

nonisolated enum KeyResolution: Equatable, Sendable {
    case key(UInt16, KeyModifiers)
    case text(String)
}

/// Si hay comando, opción o control, una letra se manda como atajo. Si no, como texto (con acentos).
/// Mayúsculas solas salen como la tecla con ⇧, para que el Mac use su propio teclado.
nonisolated enum KeyMapping {
    static func resolve(_ text: String, modifiers: KeyModifiers) -> KeyResolution {
        let shortcut = modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control)
        if shortcut, text.count == 1, let character = text.first, let code = virtualKey(for: character) {
            return .key(code, modifiers)
        }
        if modifiers.contains(.shift) {
            if text.count == 1, let character = text.first, let code = virtualKey(for: character) {
                return .key(code, modifiers)
            }
            return .text(text.uppercased())
        }
        return .text(text)
    }

    /// Bloq Mayús del iPad llega como `capsLock`, no como shift. Las dos a la vez se cancelan.
    static func hardwareModifiers(
        shift: Bool,
        capsLock: Bool,
        command: Bool,
        option: Bool,
        control: Bool
    ) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if shift != capsLock { modifiers.insert(.shift) }
        if command { modifiers.insert(.command) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    static func virtualKey(for character: Character) -> UInt16? {
        guard let key = character.lowercased().first else { return nil }
        return letters[key]
    }

    private static let letters: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        " ": 49,
    ]
}
