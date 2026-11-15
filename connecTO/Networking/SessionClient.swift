import CoreGraphics
import Foundation
import Network
import Observation

@Observable
final class SessionClient {
    enum Phase: Equatable {
        case idle
        case connecting
        case needsCode
        case controlling
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var macName = ""
    var draftCode = ""
    private(set) var notice: String?
    private(set) var videoSize = CGSize.zero
    private(set) var screenAvailable = false
    private(set) var screenDenied = false
    private(set) var displays: [SharedDisplay] = []
    private(set) var activeDisplay: UInt32 = 0
    private(set) var hearsAudio = false

    private var connection: NWConnection?
    private var endpoint: NWEndpoint?
    private var videoConnection: NWConnection?
    private var videoDecoder = VideoPacketDecoder()
    private var videoGeneration = 0
    private var videoReceiving = false
    private var onVideoPacket: ((VideoPacket) -> Void)?
    private var pendingVideo: [VideoPacket] = []
    private var decoder = FrameDecoder()
    private var identity = DeviceIdentity.load()
    private var generation = 0
    private var suppressAuto = false
    private var didReachReady = false
    private var receiving = false
    private var pendingPointer = (dx: 0.0, dy: 0.0)
    private var pointerScheduled = false
    private var pendingScroll = (dx: 0.0, dy: 0.0)
    private var scrollScheduled = false
    private let speaker = SystemAudioPlayer()

    func connect(to mac: DiscoveredMac) {
        tearDown()
        suppressAuto = false
        endpoint = mac.endpoint
        macName = mac.name
        screenDenied = false
        screenAvailable = false
        videoSize = .zero
        displays = []
        activeDisplay = 0
        hearsAudio = false
        speaker.stop()
        phase = .connecting
        notice = nil
        draftCode = ""
        let generation = generation
        let connection = NWConnection(to: mac.endpoint, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handle(state, generation: generation)
            }
        }
        connection.start(queue: .main)
    }

    func disconnect() {
        suppressAuto = true
        didReachReady = false
        tearDown()
        phase = .idle
        notice = nil
        draftCode = ""
    }

    func submitCode() {
        let digits = String(draftCode.filter(\.isNumber).prefix(6))
        guard digits.count == 6, phase == .needsCode else { return }
        sendNow(.pair(code: digits, deviceID: identity.id, deviceName: identity.name))
    }

    func reconnectIfNeeded(to macs: [DiscoveredMac]) {
        guard phase == .idle, !suppressAuto else { return }
        guard let saved = UserDefaults.standard.string(forKey: Self.lastMacKey),
              let mac = macs.first(where: { $0.name == saved }) else { return }
        connect(to: mac)
    }

    func movePointer(dx: Double, dy: Double) {
        guard phase == .controlling else { return }
        pendingPointer.dx += dx
        pendingPointer.dy += dy
        guard !pointerScheduled else { return }
        pointerScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self else { return }
            self.pointerScheduled = false
            let dx = self.pendingPointer.dx
            let dy = self.pendingPointer.dy
            self.pendingPointer = (0, 0)
            if dx != 0 || dy != 0 {
                self.sendControl(.pointer(dx: dx, dy: dy))
            }
        }
    }

    func scroll(dx: Double, dy: Double) {
        guard phase == .controlling else { return }
        pendingScroll.dx += dx
        pendingScroll.dy += dy
        guard !scrollScheduled else { return }
        scrollScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self else { return }
            self.scrollScheduled = false
            let dx = self.pendingScroll.dx
            let dy = self.pendingScroll.dy
            self.pendingScroll = (0, 0)
            if dx != 0 || dy != 0 {
                self.sendControl(.scroll(dx: dx, dy: dy))
            }
        }
    }

    func click(_ button: MouseButton) {
        sendControl(.button(button, .down))
        sendControl(.button(button, .up))
    }

    func sendControl(_ message: WireMessage) {
        guard phase == .controlling else { return }
        sendNow(message)
    }

    func sendKey(_ keyCode: UInt16, modifiers: KeyModifiers) {
        sendControl(.key(keyCode: keyCode, phase: .down, modifiers: modifiers))
        sendControl(.key(keyCode: keyCode, phase: .up, modifiers: modifiers))
    }

    func moveCursor(x: Double, y: Double) {
        sendControl(.cursor(x: x, y: y))
    }

    func attachDisplay(_ handler: @escaping (VideoPacket) -> Void) {
        onVideoPacket = handler
        for packet in pendingVideo {
            handler(packet)
        }
        pendingVideo.removeAll()
    }

    func selectDisplay(_ id: UInt32) {
        guard displays.contains(where: { $0.id == id }), id != activeDisplay else { return }
        activeDisplay = id
        sendControl(.screen(id))
    }

    func setHearsOnPad(_ enabled: Bool) {
        guard enabled != hearsAudio else { return }
        hearsAudio = enabled
        if !enabled { speaker.stop() }
        sendControl(.audio(enabled))
    }

    func sendTyped(_ text: String, modifiers: KeyModifiers) {
        switch KeyMapping.resolve(text, modifiers: modifiers) {
        case .key(let code, let modifiers):
            sendKey(code, modifiers: modifiers)
        case .text(let text):
            sendControl(.text(text))
        }
    }

    private func handle(_ state: NWConnection.State, generation: Int) {
        guard generation == self.generation else { return }
        switch state {
        case .ready:
            didReachReady = true
            sendNow(.hello(deviceID: identity.id, deviceName: identity.name, protocolVersion: ProtocolVersion.current))
            receive(generation: generation)
        case .failed:
            let allowReconnect = didReachReady
            didReachReady = false
            tearDown()
            if allowReconnect {
                phase = .idle
                suppressAuto = false
            } else {
                suppressAuto = true
                phase = .failed("No se pudo conectar con \(macName).")
            }
        case .cancelled:
            guard generation == self.generation else { return }
            tearDown()
            phase = .idle
        case .waiting, .preparing, .setup:
            break
        @unknown default:
            break
        }
    }

    private func receive(generation: Int) {
        guard !receiving, let connection else { return }
        receiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            let ended = isComplete || error != nil
            let client = self
            Task { @MainActor in
                client?.consume(data, ended: ended, generation: generation)
            }
        }
    }

    private func consume(_ data: Data?, ended: Bool, generation: Int) {
        guard generation == self.generation else { return }
        receiving = false
        if let data, !data.isEmpty {
            do {
                let messages = try decoder.append(data)
                for message in messages {
                    apply(message)
                }
            } catch {
                suppressAuto = true
                tearDown()
                phase = .failed("La conexión con \(macName) se cortó.")
                return
            }
        }
        if ended {
            let resume = didReachReady
            didReachReady = false
            tearDown()
            phase = .idle
            suppressAuto = !resume
            return
        }
        receive(generation: generation)
    }

    private func apply(_ message: WireMessage) {
        switch message {
        case .needCode:
            phase = .needsCode
        case .paired:
            phase = .controlling
            notice = nil
            UserDefaults.standard.set(macName, forKey: Self.lastMacKey)
            sendNow(.quality(longSide: Self.pictureLongSide))
            openVideo()
        case .screenUnavailable:
            screenDenied = true
            screenAvailable = false
            closeVideo()
        case .displays(let items, let active):
            displays = items
            activeDisplay = active
        case .audio(let enabled):
            hearsAudio = enabled
            if !enabled { speaker.stop() }
        case .rejected(let reason):
            draftCode = ""
            switch reason {
            case .badCode:
                notice = "Ese código no coincide."
                phase = .needsCode
            case .expiredCode:
                notice = "Ese código ya venció. Mira el nuevo en el Mac."
                phase = .needsCode
            case .unsupportedVersion:
                suppressAuto = true
                tearDown()
                phase = .failed("El Mac y el iPad no hablan la misma versión.")
            case .notPaired:
                phase = .needsCode
            }
        case .pong, .hello, .pair, .pointer, .button, .scroll, .key, .text, .media, .ping, .cursor, .quality, .videoHello, .screen:
            break
        }
    }

    private func sendNow(_ message: WireMessage) {
        guard let connection, let data = try? FrameCodec.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func openVideo() {
        guard let endpoint, videoConnection == nil else { return }
        videoGeneration += 1
        let generation = videoGeneration
        let connection = NWConnection(to: endpoint, using: .tcp)
        videoConnection = connection
        videoDecoder = VideoPacketDecoder()
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleVideo(state, generation: generation, connection: connection)
            }
        }
        connection.start(queue: .main)
    }

    private func handleVideo(_ state: NWConnection.State, generation: Int, connection: NWConnection) {
        guard generation == videoGeneration else { return }
        switch state {
        case .ready:
            guard let data = try? FrameCodec.encode(.videoHello(deviceID: identity.id)) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
            receiveVideo(generation: generation, connection: connection)
        case .failed:
            if !screenAvailable {
                screenDenied = true
            }
            closeVideo()
        case .cancelled, .waiting, .preparing, .setup:
            break
        @unknown default:
            break
        }
    }

    private func receiveVideo(generation: Int, connection: NWConnection) {
        guard !videoReceiving else { return }
        videoReceiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            let ended = isComplete || error != nil
            let client = self
            Task { @MainActor in
                client?.consumeVideo(data, ended: ended, generation: generation, connection: connection)
            }
        }
    }

    private func consumeVideo(_ data: Data?, ended: Bool, generation: Int, connection: NWConnection) {
        guard generation == videoGeneration else { return }
        videoReceiving = false
        if let data, !data.isEmpty {
            do {
                let packets = try videoDecoder.append(data)
                for packet in packets {
                    deliver(packet)
                }
            } catch {
                if !screenAvailable {
                    screenDenied = true
                }
                closeVideo()
                return
            }
        }
        if ended {
            if !screenAvailable {
                screenDenied = true
            }
            closeVideo()
            return
        }
        receiveVideo(generation: generation, connection: connection)
    }

    private func deliver(_ packet: VideoPacket) {
        switch packet {
        case .format(_, let width, let height):
            videoSize = CGSize(width: width, height: height)
            screenAvailable = true
            screenDenied = false
            forward(packet)
        case .sample:
            forward(packet)
        case .audioFormat(let sampleRate, let channels):
            guard hearsAudio else { return }
            speaker.prepare(sampleRate: sampleRate, channels: channels)
        case .audio(let data):
            guard hearsAudio else { return }
            speaker.play(data)
        }
    }

    private func forward(_ packet: VideoPacket) {
        if let onVideoPacket {
            onVideoPacket(packet)
        } else if pendingVideo.count < 30 {
            pendingVideo.append(packet)
        }
    }

    private func closeVideo() {
        videoGeneration += 1
        videoReceiving = false
        videoDecoder = VideoPacketDecoder()
        pendingVideo.removeAll()
        onVideoPacket = nil
        speaker.stop()
        let connection = videoConnection
        videoConnection = nil
        connection?.cancel()
    }

    private func tearDown() {
        generation += 1
        receiving = false
        decoder = FrameDecoder()
        displays = []
        activeDisplay = 0
        hearsAudio = false
        connection?.cancel()
        connection = nil
        closeVideo()
    }

    private static let lastMacKey = "connecTO.lastMacName"
    static let longSideKey = "connecTO.longSide"

    static var pictureLongSide: Int {
        let stored = UserDefaults.standard.integer(forKey: longSideKey)
        guard stored >= 960 else { return 1920 }
        return min(stored, 3840)
    }
}
