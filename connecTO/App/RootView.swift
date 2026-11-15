import SwiftUI

struct RootView: View {
    @State private var browser = MacBrowser()
    @State private var client = SessionClient()

    var body: some View {
        content
            .onAppear { browser.start() }
            .onChange(of: browser.macs) { _, macs in
                client.reconnectIfNeeded(to: macs)
            }
            .onChange(of: client.phase) { _, _ in
                client.reconnectIfNeeded(to: browser.macs)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch client.phase {
        case .idle:
            DiscoverView(browser: browser) { mac in
                client.connect(to: mac)
            }
        case .connecting:
            ProgressView("Conectando con \(client.macName)…")
                .padding(24)
        case .needsCode:
            PairScreen(client: client)
        case .controlling:
            ControlView(client: client, onDisconnect: client.disconnect)
        case .failed(let message):
            FailedLinkView(message: message, onBack: client.disconnect)
        }
    }
}

private struct PairScreen: View {
    @Bindable var client: SessionClient

    var body: some View {
        PairCodeView(
            macName: client.macName,
            code: $client.draftCode,
            message: client.notice,
            onSubmit: client.submitCode,
            onCancel: client.disconnect
        )
    }
}

private struct FailedLinkView: View {
    var message: String
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Volver", action: onBack)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
