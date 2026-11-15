import Foundation
import Testing
@testable import connecTO

struct WireMessageTests {
    @Test func frozenHelloJSONDecodes() throws {
        let json = """
        {"type":"hello","deviceID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","deviceName":"iPad de Greg","protocolVersion":1}
        """
        let message = try JSONDecoder().decode(WireMessage.self, from: Data(json.utf8))
        #expect(
            message == .hello(
                deviceID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
                deviceName: "iPad de Greg",
                protocolVersion: 1
            )
        )
    }

    @Test func messagesRoundTripThroughAFrame() throws {
        let messages: [WireMessage] = [
            .pointer(dx: 1.5, dy: -2),
            .media(.playPause),
            .key(keyCode: 8, phase: .down, modifiers: .command),
            .text("áéí"),
            .rejected(.badCode),
            .cursor(x: 0.25, y: 0.75),
            .quality(longSide: 1920),
        ]
        for message in messages {
            var decoder = FrameDecoder()
            let decoded = try decoder.append(FrameCodec.encode(message))
            #expect(decoded == [message])
        }
    }

    @Test func framesCanArriveInPieces() throws {
        let first = WireMessage.pointer(dx: 1.5, dy: -2)
        let second = WireMessage.media(.playPause)
        let blob = try FrameCodec.encode(first) + FrameCodec.encode(second)
        var decoder = FrameDecoder()
        let head = try decoder.append(Data(blob.prefix(3)))
        let tail = try decoder.append(Data(blob.dropFirst(3)))
        #expect(head.isEmpty)
        #expect(tail == [first, second])
    }

    @Test func oversizedFrameIsRejected() {
        var decoder = FrameDecoder()
        let header = Data([0x00, 0x00, 0x40, 0x00])
        #expect(throws: FrameError.tooLarge) {
            try decoder.append(header)
        }
    }
}
