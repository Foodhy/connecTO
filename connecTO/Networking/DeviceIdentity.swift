import Foundation
import UIKit

struct DeviceIdentity: Equatable, Sendable {
    var id: UUID
    var name: String

    static func load() -> DeviceIdentity {
        let defaults = UserDefaults.standard
        let id: UUID
        if let raw = defaults.string(forKey: "connecTO.deviceID"), let stored = UUID(uuidString: raw) {
            id = stored
        } else {
            id = UUID()
            defaults.set(id.uuidString, forKey: "connecTO.deviceID")
        }
        let name = UIDevice.current.name
        return DeviceIdentity(id: id, name: name.isEmpty ? "iPad" : name)
    }
}
