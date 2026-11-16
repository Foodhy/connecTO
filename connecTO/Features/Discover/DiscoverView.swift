import SwiftUI

struct DiscoverView: View {
    var browser: MacBrowser
    var onSelect: (DiscoveredMac, LinkMode) -> Void
    @State private var showsGuide = false
    @State private var pendingMac: DiscoveredMac?
    @State private var showsChoice = false

    var body: some View {
        NavigationStack {
            Group {
                if browser.macs.isEmpty {
                    ContentUnavailableView(
                        "Ningún Mac a la vista",
                        systemImage: "wifi",
                        description: Text("Abre connecTO en el Mac, en la misma Wi-Fi.")
                    )
                } else {
                    List(browser.macs) { mac in
                        Button {
                            pendingMac = mac
                            showsChoice = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mac.isWindows ? "desktopcomputer" : "laptopcomputer")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mac.name)
                                    Text(mac.isWindows ? "PC" : "Mac")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("connecTO")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsGuide = true
                    } label: {
                        Label("Cómo se usa", systemImage: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $showsGuide) {
                GuideView()
            }
            .confirmationDialog(
                pendingMac?.name ?? "connecTO",
                isPresented: $showsChoice,
                titleVisibility: .visible,
                presenting: pendingMac
            ) { mac in
                Button(mac.isWindows ? "Controlar el PC" : "Controlar el Mac") {
                    onSelect(mac, .control)
                }
                if !mac.isWindows {
                    Button("Monitor externo") {
                        onSelect(mac, .extend)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { mac in
                Text(mac.isWindows
                    ? "Controlar muestra una pantalla que el PC ya tiene."
                    : "Controlar muestra una pantalla que el Mac ya tiene. Monitor externo añade una pantalla más.")
            }
        }
    }
}

#Preview {
    DiscoverView(browser: MacBrowser(), onSelect: { _, _ in })
}
