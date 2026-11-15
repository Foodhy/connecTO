import SwiftUI

struct MediaBarView: View {
    var client: SessionClient

    var body: some View {
        HStack(spacing: 8) {
            ControlTile("speaker.minus", "Bajar", accessibility: "Bajar volumen") {
                client.sendControl(.media(.volumeDown))
            }
            ControlTile("speaker.slash", "Silencio") {
                client.sendControl(.media(.mute))
            }
            ControlTile("speaker.plus", "Subir", accessibility: "Subir volumen") {
                client.sendControl(.media(.volumeUp))
            }
            ControlTile("backward.end", "Previa", accessibility: "Pista anterior") {
                client.sendControl(.media(.previous))
            }
            ControlTile("playpause", "Pausa", accessibility: "Reproducir o pausar") {
                client.sendControl(.media(.playPause))
            }
            ControlTile("forward.end", "Próxima", accessibility: "Pista siguiente") {
                client.sendControl(.media(.next))
            }
        }
    }
}
