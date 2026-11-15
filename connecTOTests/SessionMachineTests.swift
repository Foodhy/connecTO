import Foundation
import Testing
@testable import connecTO

struct SessionMachineTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let device = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let session = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func wrongCodeIsRejected() {
        var machine = makeMachine(digits: "482193")
        let effect = machine.handle(pair("000000"), now: now, newSessionID: { session })
        #expect(effect == .reply(.rejected(.badCode)))
        #expect(machine.phase == .waiting)
        #expect(machine.trustedDeviceIDs.isEmpty)
    }

    @Test func expiredCodeIsRejected() {
        var machine = makeMachine(digits: "482193", lifetime: 10)
        let later = now.addingTimeInterval(10)
        let effect = machine.handle(pair("482193"), now: later, newSessionID: { session })
        #expect(effect == .reply(.rejected(.expiredCode)))
        #expect(machine.trustedDeviceIDs.isEmpty)
    }

    @Test func matchingCodePairsAndTrustsTheDevice() {
        var machine = makeMachine(digits: "482193")
        let effect = machine.handle(pair("482 193"), now: now, newSessionID: { session })
        #expect(effect == .reply(.paired(session: session)))
        #expect(machine.trustedDeviceIDs.contains(device))
        #expect(machine.phase == .paired(deviceID: device, session: session))
    }

    @Test func trustedDeviceSkipsTheCode() {
        var machine = SessionMachine(
            trustedDeviceIDs: [device],
            code: PairingCode.make(digits: "000000", now: now)
        )
        let effect = machine.handle(
            .hello(deviceID: device, deviceName: "iPad", protocolVersion: ProtocolVersion.current),
            now: now,
            newSessionID: { session }
        )
        #expect(effect == .reply(.paired(session: session)))
    }

    @Test func inputBeforePairingIsRejected() {
        var machine = makeMachine(digits: "482193")
        let effect = machine.handle(.pointer(dx: 1, dy: 2), now: now, newSessionID: { session })
        #expect(effect == .reply(.rejected(.notPaired)))
    }

    @Test func inputAfterPairingIsAccepted() {
        var machine = makeMachine(digits: "482193")
        _ = machine.handle(pair("482193"), now: now, newSessionID: { session })
        let effect = machine.handle(.pointer(dx: 4, dy: -1), now: now, newSessionID: { session })
        #expect(effect == .input(.pointer(dx: 4, dy: -1)))
    }

    @Test func replacingTheCodeInvalidatesTheOldOne() {
        var machine = makeMachine(digits: "482193")
        machine.code = PairingCode.make(digits: "111111", now: now)
        let effect = machine.handle(pair("482193"), now: now, newSessionID: { session })
        #expect(effect == .reply(.rejected(.badCode)))
    }

    @Test func unsupportedVersionIsRejected() {
        var machine = makeMachine(digits: "482193")
        let effect = machine.handle(
            .hello(deviceID: device, deviceName: "iPad", protocolVersion: 0),
            now: now,
            newSessionID: { session }
        )
        #expect(effect == .reply(.rejected(.unsupportedVersion)))
    }

    private func makeMachine(digits: String, lifetime: TimeInterval = PairingCode.lifetime) -> SessionMachine {
        SessionMachine(
            trustedDeviceIDs: [],
            code: PairingCode.make(digits: digits, now: now, lifetime: lifetime)
        )
    }

    private func pair(_ code: String) -> WireMessage {
        .pair(code: code, deviceID: device, deviceName: "iPad")
    }
}
