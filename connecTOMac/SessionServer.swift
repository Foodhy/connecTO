import Foundation
import Network

final class SessionServer {
    weak var host: MacHost?
    private var listener: NWListener?
    private var connection: NWConnection?
    private var decoder = FrameDecoder()
    private var machine: SessionMachine
    private let injector = EventInjector()
    private let store = TrustedDeviceStore()
    private var connectedDeviceName: String?
    private var pendingName: String?
    private var receiving = false
    private var restartAttempts = 0

    init(code: PairingCode) {
        let devices = store.load()
        machine = SessionMachine(trustedDeviceIDs: Set(devices.map(\.id)), code: code)
    }

    func start() throws {
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(type: "_connecto._tcp")
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.restartAttempts = 0
                case .failed:
                    self?.restart()
                default:
                    break
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func update(code: PairingCode) {
        machine.code = code
    }

    func forgetAll() {
        machine.trustedDeviceIDs = []
        machine.phase = .waiting
        store.save([])
        connectedDeviceName = nil
        pendingName = nil
        connection?.cancel()
        connection = nil
        receiving = false
        decoder = FrameDecoder()
        publish()
    }

    private func restart() {
        guard restartAttempts < 3 else { return }
        restartAttempts += 1
        listener?.cancel()
        listener = nil
        try? start()
    }

    private func accept(_ connection: NWConnection) {
        if self.connection != nil {
            connection.cancel()
            return
        }
        self.connection = connection
        decoder = FrameDecoder()
        receiving = false
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handle(state, on: connection)
            }
        }
        connection.start(queue: .main)
    }

    private func handle(_ state: NWConnection.State, on connection: NWConnection) {
        guard self.connection === connection else { return }
        switch state {
        case .ready:
            receive(on: connection)
        case .failed, .cancelled:
            closeLink()
        case .waiting, .preparing, .setup:
            break
        @unknown default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        guard !receiving else { return }
        receiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            let ended = isComplete || error != nil
            Task { @MainActor in
                self?.consume(data, ended: ended, on: connection)
            }
        }
    }

    private func consume(_ data: Data?, ended: Bool, on connection: NWConnection) {
        guard self.connection === connection else { return }
        receiving = false
        if let data, !data.isEmpty {
            do {
                let messages = try decoder.append(data)
                for message in messages {
                    handle(message)
                }
            } catch {
                connection.cancel()
                closeLink()
                return
            }
        }
        if ended {
            closeLink()
            return
        }
        receive(on: connection)
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case .hello(_, let name, _):
            pendingName = name
        case .pair(_, _, let name):
            pendingName = name
        default:
            break
        }
        let effect = machine.handle(message, now: Date())
        switch effect {
        case .reply(let reply):
            if case .paired = reply {
                connectedDeviceName = pendingName
                rememberPairedDevice(from: message)
            }
            send(reply)
        case .input(let input):
            injector.apply(input)
        case .drop:
            break
        }
        publish()
    }

    private func rememberPairedDevice(from message: WireMessage) {
        let device: TrustedDevice?
        switch message {
        case .pair(_, let id, let name):
            device = TrustedDevice(id: id, name: name, trustedAt: Date())
        case .hello(let id, let name, _):
            device = TrustedDevice(id: id, name: name, trustedAt: Date())
        default:
            device = nil
        }
        if let device {
            store.upsert(device)
        }
    }

    private func send(_ message: WireMessage) {
        guard let connection, let data = try? FrameCodec.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func closeLink() {
        connection = nil
        receiving = false
        decoder = FrameDecoder()
        connectedDeviceName = nil
        pendingName = nil
        machine.phase = .waiting
        publish()
    }

    private func publish() {
        if let connectedDeviceName {
            host?.setLink(label: "\(connectedDeviceName) conectado", linked: true)
        } else if pendingName != nil {
            host?.setLink(label: "Esperando el código", linked: false)
        } else {
            host?.setLink(label: "Esperando un iPad", linked: false)
        }
    }
}
