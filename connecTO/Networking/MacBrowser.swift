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
    return DiscoveredMac(
        id: "\(name).\(type)\(domain)",
        name: name,
        endpoint: result.endpoint,
        isWindows: windowsHost(result)
    )
}

nonisolated private func windowsHost(_ result: NWBrowser.Result) -> Bool {
    guard case .bonjour(let record) = result.metadata else { return false }
    return record["plat"] == "win"
}

nonisolated private func dedupedMacs(_ macs: [DiscoveredMac]) -> [DiscoveredMac] {
    var seen = Set<String>()
    return macs.filter { seen.insert($0.name).inserted }
}
