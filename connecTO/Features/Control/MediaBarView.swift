import SwiftUI

struct MediaBarView: View {
    var client: SessionClient

    var body: some View {
        HStack(spacing: 8) {
            symbol("speaker.minus", "Bajar volumen") { client.sendControl(.media(.volumeDown)) }
            symbol("speaker.slash", "Silencio") { client.sendControl(.media(.mute)) }
            symbol("speaker.plus", "Subir volumen") { client.sendControl(.media(.volumeUp)) }
            symbol("backward.end", "Anterior") { client.sendControl(.media(.previous)) }
            symbol("playpause", "Reproducir o pausar") { client.sendControl(.media(.playPause)) }
            symbol("forward.end", "Siguiente") { client.sendControl(.media(.next)) }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
    }

    private func symbol(_ name: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: name)
        }
        .accessibilityLabel(title)
    }
}
