import Foundation
import Observation

@Observable
final class MacHost {
    private(set) var code: PairingCode
    private(set) var now = Date()
    private(set) var accessibilityTrusted = false
    private(set) var screenRecordingAllowed = false
    private(set) var linkLabel = "Esperando un iPad"
    private(set) var isLinked = false
    private var server: SessionServer?
    private var maintainTask: Task<Void, Never>?

    init() {
        code = PairingCode.make(digits: Self.newDigits(), now: Date())
    }

    func start() {
        guard server == nil else { return }
        accessibilityTrusted = AccessibilityGate.isTrusted(prompt: true)
        let server = SessionServer(code: code)
        server.host = self
        do {
            try server.start()
        } catch {
            linkLabel = "No se pudo anunciar el Mac en la red."
        }
        self.server = server
        maintainTask = Task { @MainActor in
            while !Task.isCancelled {
                self.accessibilityTrusted = AccessibilityGate.isTrusted(prompt: false)
                self.screenRecordingAllowed = ScreenRecordingGate.isAuthorized()
                self.now = Date()
                if self.now >= self.code.expiresAt {
                    self.regenerateCode()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func regenerateCode() {
        code = PairingCode.make(digits: Self.newDigits(), now: Date())
        server?.update(code: code)
    }

    func forget() {
        server?.forgetAll()
        regenerateCode()
    }

    func openAccessibility() {
        _ = AccessibilityGate.isTrusted(prompt: true)
        AccessibilityGate.openSettings()
    }

    func openScreenRecording() {
        _ = ScreenRecordingGate.requestAccess()
        ScreenRecordingGate.openSettings()
    }

    func setLink(label: String, linked: Bool) {
        linkLabel = label
        isLinked = linked
    }

    private static func newDigits() -> String {
        var rng = SystemRandomNumberGenerator()
        return PairingCode.randomDigits(using: &rng)
    }
}
