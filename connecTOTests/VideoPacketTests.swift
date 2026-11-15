import Foundation
import Testing
@testable import connecTO

struct VideoPacketTests {
    @Test func formatAndSampleRoundTrip() throws {
        let format = VideoPacket.format(parameterSets: [Data([0, 1, 2]), Data([9])], width: 1280, height: 720)
        let sample = VideoPacket.sample(isKeyframe: true, data: Data([4, 5, 6, 7]))
        let audioFormat = VideoPacket.audioFormat(sampleRate: 48_000, channels: 2)
        let audio = VideoPacket.audio(data: Data([1, 2, 3, 4]))
        for packet in [format, sample, audioFormat, audio] {
            var decoder = VideoPacketDecoder()
            let decoded = try decoder.append(VideoPacketCodec.encode(packet))
            #expect(decoded == [packet])
        }
    }

    @Test func aPacketCanArriveInPieces() throws {
        let first = VideoPacket.format(parameterSets: [Data([1])], width: 16, height: 16)
        let second = VideoPacket.sample(isKeyframe: false, data: Data([8, 8]))
        let blob = try VideoPacketCodec.encode(first) + VideoPacketCodec.encode(second)
        var decoder = VideoPacketDecoder()
        let head = try decoder.append(Data(blob.prefix(3)))
        let tail = try decoder.append(Data(blob.dropFirst(3)))
        #expect(head.isEmpty)
        #expect(tail == [first, second])
    }

    @Test func anOversizedHeaderIsRejected() {
        var decoder = VideoPacketDecoder()
        let header = Data([0x00, 0x20, 0x00, 0x00])
        #expect(throws: VideoPacketError.tooLarge) {
            try decoder.append(header)
        }
    }
}
