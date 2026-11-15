import SwiftUI

struct ControlView: View {
    var client: SessionClient
    var onDisconnect: () -> Void
    @State private var dragArmed = false
    @State private var clickArmed = false
    @State private var keyboardVisible = false
    @AppStorage(SessionClient.longSideKey) private var longSide = 1920
    @State private var qualityTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                surface
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

    @ViewBuilder
    private var surface: some View {
        if client.screenDenied {
            VStack(spacing: 8) {
                Text("El Mac no está compartiendo la pantalla. Activa Grabación de pantalla en su menú y vuelve a conectar.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                trackpad
            }
        } else {
            ZStack {
                DesktopView(client: client, dragArmed: dragArmed, clickArmed: clickArmed)
                if !client.screenAvailable {
                    ProgressView("Abriendo la pantalla…")
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var trackpad: some View {
        TrackpadView(
            dragArmed: dragArmed,
            clickArmed: clickArmed,
            onMove: client.movePointer,
            onScroll: client.scroll,
            onLeftDown: { client.sendControl(.button(.left, .down)) },
            onLeftUp: { client.sendControl(.button(.left, .up)) },
            onLeftClick: { client.click(.left) },
            onRightClick: { client.click(.right) }
        )
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                iconButton("cursorarrow.click", "Clic", tint: clickArmed ? .orange : nil) {
                    clickArmed.toggle()
                    if clickArmed { dragArmed = false }
                }
                iconButton("contextualmenu.and.cursorarrow", "Clic derecho") { client.click(.right) }
                iconButton("hand.draw", "Arrastrar", tint: dragArmed ? .orange : nil) {
                    dragArmed.toggle()
                    if dragArmed { clickArmed = false }
                }
                iconButton(keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard", "Teclado") {
                    keyboardVisible.toggle()
                }
                spaceButton("chevron.left", SpecialKey.left, "Anterior", "Escritorio anterior")
                spaceButton("chevron.up", SpecialKey.up, "Ventanas", "Ver todas las ventanas")
                spaceButton("chevron.right", SpecialKey.right, "Siguiente", "Escritorio siguiente")
                qualityMenu
            }
        }
    }

    private var qualityMenu: some View {
        Menu {
            Text("Lado largo \(longSide) px")
            Slider(
                value: Binding(
                    get: { Double(longSide) },
                    set: { longSide = Int($0.rounded()) }
                ),
                in: 960...3840,
                step: 80
            )
        } label: {
            Image(systemName: "sparkles.tv")
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Nitidez \(longSide) px")
        .onChange(of: longSide) { _, value in
            qualityTask?.cancel()
            qualityTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                client.sendControl(.quality(longSide: value))
            }
        }
    }

    private func spaceButton(_ systemName: String, _ key: UInt16, _ caption: String, _ title: String) -> some View {
        Button {
            client.sendControl(.key(keyCode: key, phase: .down, modifiers: .control))
            Task {
                try? await Task.sleep(for: .milliseconds(40))
                client.sendControl(.key(keyCode: key, phase: .up, modifiers: .control))
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                Text(caption)
                    .font(.caption2)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func iconButton(
        _ systemName: String,
        _ title: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
        if let tint {
            button.tint(tint)
        } else {
            button
        }
    }
}
