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

    private var connection: NWConnection?
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

    func connect(to mac: DiscoveredMac) {
        tearDown()
        suppressAuto = false
        macName = mac.name
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
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
            Task { @MainActor in
                self?.consume(data, ended: ended, generation: generation)
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
        case .pong, .hello, .pair, .pointer, .button, .scroll, .key, .text, .media, .ping:
            break
        }
    }

    private func sendNow(_ message: WireMessage) {
        guard let connection, let data = try? FrameCodec.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func tearDown() {
        generation += 1
        receiving = false
        decoder = FrameDecoder()
        connection?.cancel()
        connection = nil
    }

    private static let lastMacKey = "connecTO.lastMacName"
}
