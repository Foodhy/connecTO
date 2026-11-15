import CoreGraphics
import Darwin

/// En macOS 15 o posterior Control+flecha no cambia el escritorio: la flecha
/// llega a la app de delante. Mission Control se abre con la notificación del
/// Dock, y el escritorio se mueve con el gesto horizontal del trackpad.
enum DesktopMotion {
    static func perform(arrow: UInt16, frame: CGRect) {
        switch arrow {
        case SpecialKey.up:
            notify("com.apple.expose.awake")
        case SpecialKey.down:
            notify("com.apple.expose.front.awake")
        case SpecialKey.left:
            swipe(sign: -1, frame: frame)
        case SpecialKey.right:
            swipe(sign: 1, frame: frame)
        default:
            break
        }
    }

    private static let notifyDock: (@convention(c) (CFString) -> Void)? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Void).self)
    }()

    private static func notify(_ name: String) {
        notifyDock?(name as CFString)
    }

    private static func swipe(sign: Double, frame: CGRect) {
        let saved = CGEvent(source: nil)?.location
        if frame.width > 1, frame.height > 1 {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        }
        guard let event = CGEvent(source: nil) else { return }
        event.setIntegerValueField(CGEventField(rawValue: 55)!, value: 30)
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23)
        event.setIntegerValueField(CGEventField(rawValue: 123)!, value: 1)
        event.setDoubleValueField(CGEventField(rawValue: 124)!, value: sign)
        event.setDoubleValueField(CGEventField(rawValue: 129)!, value: sign * 9999)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: 1)
        event.post(tap: .cgSessionEventTap)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: 4)
        event.post(tap: .cgSessionEventTap)
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }
}
