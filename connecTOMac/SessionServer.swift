import CoreGraphics
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
    private var videoConnection: NWConnection?
    private var videoDecoder = FrameDecoder()
    private var videoReceiving = false
    private let capturer = ScreenCapturer()
    private var displayFrame = CGRect.zero
    private var preferredLongSide = 1920
    private var capturing = false
    private var captureGeneration = 0

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
        closeVideo()
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
        if self.connection == nil {
            self.connection = connection
            decoder = FrameDecoder()
            receiving = false
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handle(state, on: connection)
                }
            }
            connection.start(queue: .main)
            return
        }
        guard videoConnection == nil, pairedDeviceID != nil else {
            connection.cancel()
            return
        }
        videoConnection = connection
        videoDecoder = FrameDecoder()
        videoReceiving = false
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleVideo(state, on: connection)
            }
        }
        connection.start(queue: .main)
    }

    private var pairedDeviceID: UUID? {
        if case .paired(let deviceID, _) = machine.phase { return deviceID }
        return nil
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
            if case .quality(let longSide) = input {
                applyQuality(longSide)
            } else {
                injector.apply(input, displayFrame: displayFrame)
            }
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

    private func handleVideo(_ state: NWConnection.State, on connection: NWConnection) {
        guard videoConnection === connection else { return }
        switch state {
        case .ready:
            receiveVideo(on: connection)
        case .failed, .cancelled:
            closeVideo()
        case .waiting, .preparing, .setup:
            break
        @unknown default:
            break
        }
    }

    private func receiveVideo(on connection: NWConnection) {
        guard !videoReceiving else { return }
        videoReceiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            let ended = isComplete || error != nil
            Task { @MainActor in
                self?.consumeVideo(data, ended: ended, on: connection)
            }
        }
    }

    private func consumeVideo(_ data: Data?, ended: Bool, on connection: NWConnection) {
        guard videoConnection === connection else { return }
        videoReceiving = false
        if let data, !data.isEmpty, !capturing {
            do {
                let messages = try videoDecoder.append(data)
                for message in messages {
                    acceptVideoHello(message)
                    if videoConnection == nil { return }
                }
            } catch {
                closeVideo()
                return
            }
        }
        if ended {
            closeVideo()
            return
        }
        receiveVideo(on: connection)
    }

    private func acceptVideoHello(_ message: WireMessage) {
        guard case .videoHello(let deviceID) = message, deviceID == pairedDeviceID else {
            closeVideo()
            return
        }
        guard ScreenRecordingGate.isAuthorized() || ScreenRecordingGate.requestAccess() else {
            send(.screenUnavailable)
            closeVideo()
            return
        }
        beginCapture()
    }

    private func applyQuality(_ longSide: Int) {
        let clamped = min(max(longSide, 960), 8192)
        let changed = clamped != preferredLongSide
        preferredLongSide = clamped
        guard changed, capturing else { return }
        restartCapture()
    }

    private func restartCapture() {
        captureGeneration += 1
        capturing = false
        capturer.stop()
        beginCapture()
    }

    private func beginCapture() {
        guard !capturing else { return }
        capturing = true
        captureGeneration += 1
        let generation = captureGeneration
        capturer.onPacket = { [weak self] packet in
            guard let data = try? VideoPacketCodec.encode(packet) else { return }
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else { return }
                self.sendVideo(data)
            }
        }
        capturer.onFailure = { [weak self] in
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else { return }
                self.send(.screenUnavailable)
                self.closeVideo()
            }
        }
        Task { @MainActor in
            do {
                let frame = try await capturer.start(longSide: preferredLongSide)
                guard captureGeneration == generation else { return }
                displayFrame = frame
            } catch CaptureError.replaced {
                return
            } catch {
                guard captureGeneration == generation else { return }
                send(.screenUnavailable)
                closeVideo()
            }
        }
    }

    private func sendVideo(_ data: Data) {
        videoConnection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func closeVideo() {
        capturing = false
        captureGeneration += 1
        displayFrame = .zero
        capturer.stop()
        let connection = videoConnection
        videoConnection = nil
        videoReceiving = false
        videoDecoder = FrameDecoder()
        connection?.cancel()
    }

    private func closeLink() {
        connection = nil
        receiving = false
        decoder = FrameDecoder()
        connectedDeviceName = nil
        pendingName = nil
        machine.phase = .waiting
        closeVideo()
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
