import SwiftUI

@main
struct connecTOMacApp: App {
    @State private var host: MacHost

    init() {
        let host = MacHost()
        _host = State(initialValue: host)
        host.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuStatusView(host: host)
        } label: {
            Image(systemName: host.isLinked ? "ipad" : "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}
