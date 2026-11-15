import Foundation

nonisolated enum ProtocolVersion {
    static let current = 1
}

nonisolated enum RejectReason: String, Codable, Equatable, Sendable {
    case badCode
    case expiredCode
    case unsupportedVersion
    case notPaired
}

nonisolated enum MouseButton: String, Codable, Equatable, Sendable {
    case left
    case right
}

nonisolated enum ButtonPhase: String, Codable, Equatable, Sendable {
    case down
    case up
}

nonisolated struct KeyModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
}

nonisolated enum MediaAction: String, Codable, Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case next
    case previous
}

nonisolated enum SpecialKey {
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}

/// Mensajes de la sesión. El JSON es estable: un cliente futuro tiene que poder leer estos `type`.
nonisolated enum WireMessage: Equatable, Sendable {
    case hello(deviceID: UUID, deviceName: String, protocolVersion: Int)
    case pair(code: String, deviceID: UUID, deviceName: String)
    case paired(session: UUID)
    case needCode
    case rejected(RejectReason)
    case pointer(dx: Double, dy: Double)
    case button(MouseButton, ButtonPhase)
    case scroll(dx: Double, dy: Double)
    case key(keyCode: UInt16, phase: ButtonPhase, modifiers: KeyModifiers)
    case text(String)
    case media(MediaAction)
    case cursor(x: Double, y: Double)
    case quality(longSide: Int)
    case videoHello(deviceID: UUID)
    case screenUnavailable
    case ping
    case pong
}

nonisolated extension WireMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case dx
        case dy
        case code
        case deviceID
        case deviceName
        case protocolVersion
        case session
        case reason
        case button
        case phase
        case keyCode
        case modifiers
        case text
        case action
        case x
        case y
        case longSide
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let deviceID, let deviceName, let protocolVersion):
            try container.encode("hello", forKey: .type)
            try container.encode(deviceID.uuidString, forKey: .deviceID)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        case .pair(let code, let deviceID, let deviceName):
            try container.encode("pair", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(deviceID.uuidString, forKey: .deviceID)
            try container.encode(deviceName, forKey: .deviceName)
        case .paired(let session):
            try container.encode("paired", forKey: .type)
            try container.encode(session.uuidString, forKey: .session)
        case .needCode:
            try container.encode("needCode", forKey: .type)
        case .rejected(let reason):
            try container.encode("rejected", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .pointer(let dx, let dy):
            try container.encode("pointer", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .button(let button, let phase):
            try container.encode("button", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(phase, forKey: .phase)
        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .key(let keyCode, let phase, let modifiers):
            try container.encode("key", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(phase, forKey: .phase)
            try container.encode(modifiers.rawValue, forKey: .modifiers)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .media(let action):
            try container.encode("media", forKey: .type)
            try container.encode(action, forKey: .action)
        case .cursor(let x, let y):
            try container.encode("cursor", forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .quality(let longSide):
            try container.encode("quality", forKey: .type)
            try container.encode(longSide, forKey: .longSide)
        case .videoHello(let deviceID):
            try container.encode("videoHello", forKey: .type)
            try container.encode(deviceID.uuidString, forKey: .deviceID)
        case .screenUnavailable:
            try container.encode("screenUnavailable", forKey: .type)
        case .ping:
            try container.encode("ping", forKey: .type)
        case .pong:
            try container.encode("pong", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            self = .hello(
                deviceID: try Self.uuid(from: container, forKey: .deviceID),
                deviceName: try container.decode(String.self, forKey: .deviceName),
                protocolVersion: try container.decode(Int.self, forKey: .protocolVersion)
            )
        case "pair":
            self = .pair(
                code: try container.decode(String.self, forKey: .code),
                deviceID: try Self.uuid(from: container, forKey: .deviceID),
                deviceName: try container.decode(String.self, forKey: .deviceName)
            )
        case "paired":
            self = .paired(session: try Self.uuid(from: container, forKey: .session))
        case "needCode":
            self = .needCode
        case "rejected":
            self = .rejected(try container.decode(RejectReason.self, forKey: .reason))
        case "pointer":
            self = .pointer(
                dx: try container.decode(Double.self, forKey: .dx),
                dy: try container.decode(Double.self, forKey: .dy)
            )
        case "button":
            self = .button(
                try container.decode(MouseButton.self, forKey: .button),
                try container.decode(ButtonPhase.self, forKey: .phase)
            )
        case "scroll":
            self = .scroll(
                dx: try container.decode(Double.self, forKey: .dx),
                dy: try container.decode(Double.self, forKey: .dy)
            )
        case "key":
            self = .key(
                keyCode: try container.decode(UInt16.self, forKey: .keyCode),
                phase: try container.decode(ButtonPhase.self, forKey: .phase),
                modifiers: KeyModifiers(rawValue: try container.decode(Int.self, forKey: .modifiers))
            )
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "media":
            self = .media(try container.decode(MediaAction.self, forKey: .action))
        case "cursor":
            self = .cursor(
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        case "quality":
            self = .quality(longSide: try container.decode(Int.self, forKey: .longSide))
        case "videoHello":
            self = .videoHello(deviceID: try Self.uuid(from: container, forKey: .deviceID))
        case "screenUnavailable":
            self = .screenUnavailable
        case "ping":
            self = .ping
        case "pong":
            self = .pong
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Tipo de mensaje desconocido: \(type)"
            )
        }
    }

    private static func uuid(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UUID {
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "UUID inválido"
            )
        }
        return uuid
    }
}
