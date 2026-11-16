import SwiftUI

struct DiscoverView: View {
    var browser: MacBrowser
    var onSelect: (DiscoveredMac, LinkMode) -> Void
    @State private var showsGuide = false

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
                        HStack(spacing: 12) {
                            Image(systemName: mac.isWindows ? "desktopcomputer" : "laptopcomputer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.name)
                                Text(mac.isWindows ? "PC" : "Mac")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button {
                                    onSelect(mac, .control)
                                } label: {
                                    Label("Controlador", systemImage: "cursorarrow.click")
                                }
                                Button {
                                    onSelect(mac, .extend)
                                } label: {
                                    Label("Monitor", systemImage: "display")
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                        }
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
        }
    }
}

#Preview {
    DiscoverView(browser: MacBrowser(), onSelect: { _, _ in })
}
