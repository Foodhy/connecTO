import Foundation

nonisolated struct TrustedDevice: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var trustedAt: Date
}
