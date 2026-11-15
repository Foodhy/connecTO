import SwiftUI

struct ControlView: View {
    var client: SessionClient
    var onDisconnect: () -> Void
    @State private var dragArmed = false
    @State private var clickArmed = false
    @State private var keyboardVisible = false
    @State private var windowsOpen = false
    @State private var confirmDisconnect = false
    @AppStorage(SessionClient.longSideKey) private var longSide = 1920
    @State private var qualityTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                surface
                if keyboardVisible {
                    KeyboardBarView(client: client)
                }
                actionRow
            }
            .padding(16)
            .navigationTitle(client.macName)
            .navigationBarTitleDisplayMode(.inline)
            .alert("¿Seguro que quieres desconectar?", isPresented: $confirmDisconnect) {
                Button("Desconectar", role: .destructive, action: onDisconnect)
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se cierra la sesión con \(client.macName).")
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
                ControlTile("cursorarrow.click", "Clic", tint: clickArmed ? .orange : nil) {
                    clickArmed.toggle()
                    if clickArmed { dragArmed = false }
                }
                ControlTile("contextualmenu.and.cursorarrow", "Derecho", accessibility: "Clic derecho") {
                    client.click(.right)
                }
                ControlTile("hand.draw", "Arrastrar", tint: dragArmed ? .orange : nil) {
                    dragArmed.toggle()
                    if dragArmed { clickArmed = false }
                }
                ControlTile(keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard", "Teclado") {
                    keyboardVisible.toggle()
                }
                ControlTile("chevron.left", "Anterior", accessibility: "Escritorio anterior") {
                    sendSpace(SpecialKey.left)
                }
                ControlTile(
                    windowsOpen ? "chevron.down" : "chevron.up",
                    "Ventanas",
                    accessibility: windowsOpen ? "Ventanas de esta app" : "Ver todas las ventanas"
                ) {
                    sendWindows()
                }
                ControlTile("chevron.right", "Siguiente", accessibility: "Escritorio siguiente") {
                    sendSpace(SpecialKey.right)
                }
                displayMenu
                soundMenu
                MediaBarView(client: client)
                qualityMenu
                ControlTile("power", "Desconectar", tint: .red, prominent: true) {
                    confirmDisconnect = true
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var displayMenu: some View {
        Menu {
            if client.displays.isEmpty {
                Text("Buscando pantallas…")
            } else {
                ForEach(client.displays, id: \.id) { display in
                    Button {
                        client.selectDisplay(display.id)
                    } label: {
                        screenLabel(display)
                    }
                }
            }
        } label: {
            ControlTileLabel(systemName: "display")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Pantalla")
    }

    private var soundMenu: some View {
        Menu {
            Button {
                client.setHearsOnPad(false)
            } label: {
                if client.hearsAudio {
                    Text("En el Mac")
                } else {
                    Label("En el Mac", systemImage: "checkmark")
                }
            }
            Button {
                client.setHearsOnPad(true)
            } label: {
                if client.hearsAudio {
                    Label("En el iPad", systemImage: "checkmark")
                } else {
                    Text("En el iPad")
                }
            }
        } label: {
            ControlTileLabel(systemName: client.hearsAudio ? "ipad.gen2" : "speaker.wave.2")
        }
        .buttonStyle(.bordered)
        .tint(client.hearsAudio ? .orange : nil)
        .accessibilityLabel(client.hearsAudio ? "Sonido en el iPad" : "Sonido en el Mac")
    }

    @ViewBuilder
    private func screenLabel(_ display: SharedDisplay) -> some View {
        let title = "\(display.name) \(display.width)×\(display.height)"
        if display.id == client.activeDisplay {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
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
            ControlTileLabel(systemName: "sparkles.tv")
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

    private func sendSpace(_ key: UInt16) {
        client.sendControl(.key(keyCode: key, phase: .down, modifiers: .control))
    }

    private func sendWindows() {
        let key = SpaceChord.windowsArrow(alreadyOpen: windowsOpen)
        windowsOpen.toggle()
        sendSpace(key)
    }
}
