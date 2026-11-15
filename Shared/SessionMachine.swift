import Foundation

/// Decide qué hacer con cada mensaje antes de tocar el cursor.
/// No sabe de red ni de `CGEvent`: solo del código, de los iPads de confianza y de si la sesión ya está abierta.
nonisolated struct SessionMachine: Equatable, Sendable {
    var trustedDeviceIDs: Set<UUID>
    var code: PairingCode
    var phase: Phase

    enum Phase: Equatable, Sendable {
        case waiting
        case paired(deviceID: UUID, session: UUID)
    }

    enum Effect: Equatable, Sendable {
        case reply(WireMessage)
        case input(WireMessage)
        case drop
    }

    init(trustedDeviceIDs: Set<UUID>, code: PairingCode) {
        self.trustedDeviceIDs = trustedDeviceIDs
        self.code = code
        self.phase = .waiting
    }

    mutating func handle(
        _ message: WireMessage,
        now: Date,
        newSessionID: () -> UUID = { UUID() }
    ) -> Effect {
        switch message {
        case .hello(let deviceID, _, let version):
            guard version == ProtocolVersion.current else {
                return .reply(.rejected(.unsupportedVersion))
            }
            guard trustedDeviceIDs.contains(deviceID) else {
                return .reply(.needCode)
            }
            return pair(deviceID, newSessionID: newSessionID())
        case .pair(let entry, let deviceID, _):
            switch code.matches(entry, at: now) {
            case .expired:
                return .reply(.rejected(.expiredCode))
            case .mismatch:
                return .reply(.rejected(.badCode))
            case .match:
                trustedDeviceIDs.insert(deviceID)
                return pair(deviceID, newSessionID: newSessionID())
            }
        case .pointer, .button, .scroll, .key, .text, .media, .cursor, .quality:
            guard case .paired = phase else {
                return .reply(.rejected(.notPaired))
            }
            return .input(message)
        case .ping:
            return .reply(.pong)
        case .paired, .needCode, .rejected, .pong, .videoHello, .screenUnavailable:
            return .drop
        }
    }

    private mutating func pair(_ deviceID: UUID, newSessionID: UUID) -> Effect {
        phase = .paired(deviceID: deviceID, session: newSessionID)
        return .reply(.paired(session: newSessionID))
    }
}
