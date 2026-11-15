import SwiftUI

struct DiscoverView: View {
    var browser: MacBrowser
    var onSelect: (DiscoveredMac) -> Void
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
                        Button {
                            onSelect(mac)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "laptopcomputer")
                                Text(mac.name)
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
        }
    }
}

#Preview {
    DiscoverView(browser: MacBrowser(), onSelect: { _ in })
}
