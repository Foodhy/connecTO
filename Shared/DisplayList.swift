import Foundation

nonisolated struct SharedDisplay: Codable, Equatable, Sendable {
    var id: UInt32
    var name: String
    var width: Int
    var height: Int
}

/// La pantalla principal va primero. Si la elegida ya no está, se vuelve a la principal.
nonisolated enum DisplayList {
    static func ordered(_ displays: [SharedDisplay], mainID: UInt32) -> [SharedDisplay] {
        displays.enumerated().sorted { lhs, rhs in
            let leftIsMain = lhs.element.id == mainID
            let rightIsMain = rhs.element.id == mainID
            if leftIsMain != rightIsMain { return leftIsMain }
            let name = lhs.element.name.localizedStandardCompare(rhs.element.name)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func resolvedID(preferred: UInt32?, displays: [SharedDisplay], mainID: UInt32) -> UInt32? {
        if let preferred, displays.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if displays.contains(where: { $0.id == mainID }) {
            return mainID
        }
        return displays.first?.id
    }
}
