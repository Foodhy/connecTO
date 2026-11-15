import Foundation
import Testing
@testable import connecTO

struct PairingCodeTests {
    @Test func groupsSixDigits() {
        #expect(PairingCode.grouped("482193") == "482 193")
    }

    @Test func spacesStillMatch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let code = PairingCode.make(digits: "482193", now: now, lifetime: 30)
        #expect(code.matches("482 193", at: now) == .match)
        #expect(code.matches("000000", at: now) == .mismatch)
        #expect(code.matches("482193", at: now.addingTimeInterval(30)) == .expired)
    }

    @Test func randomCodeIsSixDigits() {
        var rng = SystemRandomNumberGenerator()
        let digits = PairingCode.randomDigits(using: &rng)
        #expect(digits.count == 6)
        #expect(digits.range(of: #"^\d{6}$"#, options: .regularExpression) != nil)
    }
}
