import Foundation

nonisolated struct PairingCode: Equatable, Sendable {
    var digits: String
    var expiresAt: Date

    static let length = 6
    static let lifetime: TimeInterval = 180

    enum Match: Equatable, Sendable {
        case match
        case mismatch
        case expired
    }

    func matches(_ entry: String, at now: Date) -> Match {
        if now >= expiresAt { return .expired }
        let normalized = entry.filter(\.isNumber)
        if normalized.count == Self.length, normalized == digits { return .match }
        return .mismatch
    }

    static func grouped(_ digits: String) -> String {
        guard digits.count == length else { return digits }
        let split = digits.index(digits.startIndex, offsetBy: 3)
        return "\(digits[..<split]) \(digits[split...])"
    }

    static func randomDigits<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let value = Int.random(in: 0...999_999, using: &rng)
        return String(format: "%06d", value)
    }

    static func make(digits: String, now: Date, lifetime: TimeInterval = PairingCode.lifetime) -> PairingCode {
        PairingCode(digits: digits, expiresAt: now.addingTimeInterval(lifetime))
    }
}
