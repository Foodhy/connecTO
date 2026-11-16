import Foundation
import Network
import Observation

nonisolated struct DiscoveredMac: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var endpoint: NWEndpoint
    var isWindows: Bool
}

@Observable
final class MacBrowser {
    private(set) var macs: [DiscoveredMac] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_connecto._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = dedupedMacs(results.compactMap(discoveredMac))
            Task { @MainActor in
                self?.macs = found
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }
}

nonisolated private func discoveredMac(_ result: NWBrowser.Result) -> DiscoveredMac? {
    guard case .service(let name, let type, let domain, _) = result.endpoint else { return nil }
    let windows = windowsHost(name, result)
    return DiscoveredMac(
        id: "\(name).\(type)\(domain)",
        name: displayName(name, windows: windows),
        endpoint: result.endpoint,
        isWindows: windows
    )
}

nonisolated private func windowsHost(_ name: String, _ result: NWBrowser.Result) -> Bool {
    if name.hasSuffix(" PC") { return true }
    guard case .bonjour(let record) = result.metadata else { return false }
    return record["plat"] == "win"
}

nonisolated private func displayName(_ name: String, windows: Bool) -> String {
    guard windows, name.hasSuffix(" PC") else { return name }
    return String(name.dropLast(3))
}

nonisolated private func dedupedMacs(_ macs: [DiscoveredMac]) -> [DiscoveredMac] {
    var seen = Set<String>()
    return macs.filter { seen.insert($0.id).inserted }
}
