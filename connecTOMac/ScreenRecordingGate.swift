import AppKit
import CoreGraphics

enum ScreenRecordingGate {
    static func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
