import SwiftUI

struct MenuStatusView: View {
    var host: MacHost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Código")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(PairingCode.grouped(host.code.digits))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Vence en \(remaining)")
                .foregroundStyle(.secondary)
            Text(host.linkLabel)
            if host.accessibilityTrusted {
                Text("Accesibilidad activa")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Falta Accesibilidad. Sin ese permiso el Mac ignora el mando.")
                    .font(.callout)
                Button("Abrir Ajustes de Accesibilidad", action: host.openAccessibility)
            }
            Button("Nuevo código", action: host.regenerateCode)
            Button("Olvidar iPads", action: host.forget)
            Divider()
            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var remaining: String {
        let seconds = max(0, Int(host.code.expiresAt.timeIntervalSince(host.now).rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
