import SwiftUI

struct KeyboardBarView: View {
    var client: SessionClient
    @State private var draft = ""
    @State private var modifiers = KeyModifiers()

    var body: some View {
        VStack(spacing: 8) {
            TextField("Escribe…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { client.sendKey(SpecialKey.return, modifiers: modifiers) }
                .onChange(of: draft) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    client.sendTyped(newValue, modifiers: modifiers)
                    draft = ""
                }
            HStack(spacing: 8) {
                modifierButton("⌘", flag: .command)
                modifierButton("⌥", flag: .option)
                modifierButton("⇧", flag: .shift)
                modifierButton("⌃", flag: .control)
            }
            HStack(spacing: 8) {
                keyButton("esc") { client.sendKey(SpecialKey.escape, modifiers: modifiers) }
                keyButton("tab") { client.sendKey(SpecialKey.tab, modifiers: modifiers) }
                keyButton("⌫") { client.sendKey(SpecialKey.delete, modifiers: modifiers) }
                keyButton("↩") { client.sendKey(SpecialKey.return, modifiers: modifiers) }
            }
            HStack(spacing: 8) {
                keyButton("←") { client.sendKey(SpecialKey.left, modifiers: modifiers) }
                keyButton("→") { client.sendKey(SpecialKey.right, modifiers: modifiers) }
                keyButton("↑") { client.sendKey(SpecialKey.up, modifiers: modifiers) }
                keyButton("↓") { client.sendKey(SpecialKey.down, modifiers: modifiers) }
            }
        }
    }

    private func modifierButton(_ title: String, flag: KeyModifiers) -> some View {
        Button(title) {
            if modifiers.contains(flag) {
                modifiers.remove(flag)
            } else {
                modifiers.insert(flag)
            }
        }
        .buttonStyle(.bordered)
        .tint(modifiers.contains(flag) ? .accentColor : .secondary)
    }

    private func keyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}
