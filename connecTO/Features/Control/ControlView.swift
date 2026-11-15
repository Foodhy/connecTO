import SwiftUI

struct ControlView: View {
    var client: SessionClient
    var onDisconnect: () -> Void
    @State private var dragArmed = false
    @State private var keyboardVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TrackpadView(
                    dragArmed: dragArmed,
                    onMove: client.movePointer,
                    onScroll: client.scroll,
                    onLeftDown: { client.sendControl(.button(.left, .down)) },
                    onLeftUp: { client.sendControl(.button(.left, .up)) },
                    onLeftClick: { client.click(.left) },
                    onRightClick: { client.click(.right) }
                )
                actionRow
                if keyboardVisible {
                    KeyboardBarView(client: client)
                }
                MediaBarView(client: client)
            }
            .padding(16)
            .navigationTitle(client.macName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Desconectar", action: onDisconnect)
                }
            }
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("Clic") { client.click(.left) }
                Button("Derecho") { client.click(.right) }
                Button(dragArmed ? "Soltar" : "Arrastrar") { dragArmed.toggle() }
                    .tint(dragArmed ? .orange : nil)
                Button(keyboardVisible ? "Ocultar teclado" : "Teclado") { keyboardVisible.toggle() }
            }
            .buttonStyle(.bordered)
        }
    }
}
