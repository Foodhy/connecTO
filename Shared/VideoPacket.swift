import Foundation

nonisolated enum VideoPacket: Equatable, Sendable {
    case format(parameterSets: [Data], width: Int, height: Int)
    case sample(isKeyframe: Bool, data: Data)
    case audioFormat(sampleRate: Int, channels: Int)
    case audio(data: Data)
}

nonisolated enum VideoPacketError: Error, Equatable {
    case tooLarge
    case malformed
}

nonisolated enum VideoPacketCodec {
    static let maxFrameBytes = 2_000_000

    static func encode(_ packet: VideoPacket) throws -> Data {
        let payload = try payload(for: packet)
        guard payload.count <= maxFrameBytes else { throw VideoPacketError.tooLarge }
        var frame = Data(capacity: 4 + payload.count)
        appendUInt32(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    static func decode(_ payload: Data) throws -> VideoPacket {
        guard let kind = payload.first else { throw VideoPacketError.malformed }
        switch kind {
        case 1:
            guard payload.count >= 7 else { throw VideoPacketError.malformed }
            let width = readUInt16(payload, at: 1)
            let height = readUInt16(payload, at: 3)
            let count = readUInt16(payload, at: 5)
            var index = 7
            var sets: [Data] = []
            sets.reserveCapacity(count)
            for _ in 0..<count {
                guard index + 4 <= payload.count else { throw VideoPacketError.malformed }
                let size = readUInt32(payload, at: index)
                index += 4
                guard index + size <= payload.count else { throw VideoPacketError.malformed }
                sets.append(Data(payload[index..<(index + size)]))
                index += size
            }
            return .format(parameterSets: sets, width: width, height: height)
        case 2:
            guard payload.count >= 2 else { throw VideoPacketError.malformed }
            let isKeyframe = payload[payload.startIndex + 1] == 1
            return .sample(isKeyframe: isKeyframe, data: Data(payload.dropFirst(2)))
        case 3:
            guard payload.count == 7 else { throw VideoPacketError.malformed }
            return .audioFormat(
                sampleRate: readUInt32(payload, at: payload.startIndex + 1),
                channels: readUInt16(payload, at: 5)
            )
        case 4:
            guard payload.count >= 2 else { throw VideoPacketError.malformed }
            return .audio(data: Data(payload.dropFirst(1)))
        default:
            throw VideoPacketError.malformed
        }
    }

    private static func payload(for packet: VideoPacket) throws -> Data {
        switch packet {
        case .format(let sets, let width, let height):
            guard width >= 0, width <= Int(UInt16.max), height >= 0, height <= Int(UInt16.max) else {
                throw VideoPacketError.malformed
            }
            guard sets.count <= Int(UInt16.max) else { throw VideoPacketError.malformed }
            var data = Data()
            data.append(1)
            appendUInt16(UInt16(width), to: &data)
            appendUInt16(UInt16(height), to: &data)
            appendUInt16(UInt16(sets.count), to: &data)
            for set in sets {
                guard set.count <= Int(UInt32.max) else { throw VideoPacketError.malformed }
                appendUInt32(UInt32(set.count), to: &data)
                data.append(set)
            }
            return data
        case .sample(let isKeyframe, let sample):
            var data = Data()
            data.append(2)
            data.append(isKeyframe ? 1 : 0)
            data.append(sample)
            return data
        case .audioFormat(let sampleRate, let channels):
            guard sampleRate >= 0, sampleRate <= Int(UInt32.max), channels >= 0, channels <= Int(UInt16.max) else {
                throw VideoPacketError.malformed
            }
            var data = Data()
            data.append(3)
            appendUInt32(UInt32(sampleRate), to: &data)
            appendUInt16(UInt16(channels), to: &data)
            return data
        case .audio(let sample):
            guard !sample.isEmpty else { throw VideoPacketError.malformed }
            var data = Data()
            data.append(4)
            data.append(sample)
            return data
        }
    }
}

nonisolated struct VideoPacketDecoder: Sendable {
    private var buffer = Data()

    mutating func append(_ chunk: Data) throws -> [VideoPacket] {
        buffer.append(chunk)
        var packets: [VideoPacket] = []
        while buffer.count >= 4 {
            let length = readUInt32(buffer, at: buffer.startIndex)
            guard length > 0, length <= VideoPacketCodec.maxFrameBytes else {
                buffer.removeAll()
                throw VideoPacketError.tooLarge
            }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            let payload = Data(buffer[start..<(start + length)])
            buffer.removeFirst(4 + length)
            packets.append(try VideoPacketCodec.decode(payload))
        }
        return packets
    }
}

nonisolated private func appendUInt16(_ value: UInt16, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

nonisolated private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

nonisolated private func readUInt16(_ data: Data, at offset: Int) -> Int {
    let start = data.startIndex + offset
    return (Int(data[start]) << 8) | Int(data[start + 1])
}

nonisolated private func readUInt32(_ data: Data, at index: Data.Index) -> Int {
    let byte0 = Int(data[index])
    let byte1 = Int(data[index + 1])
    let byte2 = Int(data[index + 2])
    let byte3 = Int(data[index + 3])
    return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
}
