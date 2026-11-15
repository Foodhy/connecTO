import Foundation

nonisolated enum FrameError: Error, Equatable {
    case tooLarge
}

nonisolated enum FrameCodec {
    static let maxFrameBytes = 8_192

    static func encode(_ message: WireMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maxFrameBytes else { throw FrameError.tooLarge }
        var frame = Data(capacity: 4 + payload.count)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }
}

nonisolated struct FrameDecoder: Sendable {
    private var buffer = Data()

    mutating func append(_ chunk: Data) throws -> [WireMessage] {
        buffer.append(chunk)
        var messages: [WireMessage] = []
        while buffer.count >= 4 {
            let length = readLength()
            guard length > 0, length <= FrameCodec.maxFrameBytes else {
                buffer.removeAll()
                throw FrameError.tooLarge
            }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            let payload = Data(buffer[start..<(start + length)])
            buffer.removeFirst(4 + length)
            messages.append(try JSONDecoder().decode(WireMessage.self, from: payload))
        }
        return messages
    }

    private func readLength() -> Int {
        let start = buffer.startIndex
        let byte0 = Int(buffer[start])
        let byte1 = Int(buffer[start + 1])
        let byte2 = Int(buffer[start + 2])
        let byte3 = Int(buffer[start + 3])
        return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
    }
}
