import Foundation

struct TrustedDeviceStore {
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("connecTO/trusted-devices.json")
    }

    func load() -> [TrustedDevice] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TrustedDevice].self, from: data)) ?? []
    }

    func save(_ devices: [TrustedDevice]) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(devices) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func upsert(_ device: TrustedDevice) {
        var devices = load().filter { $0.id != device.id }
        devices.append(device)
        save(devices)
    }
}
