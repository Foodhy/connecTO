import AppKit
import CoreGraphics

final class EventInjector {
    private let source = CGEventSource(stateID: .combinedSessionState)
    /// Mission Control ignora teclas que no parecen de un teclado real.
    private let keyboardSource = CGEventSource(stateID: .hidSystemState)
    private let chordQueue = DispatchQueue(label: "connecto.space-chord")
    private var leftIsDown = false
    private var rightIsDown = false
    private var leftClickCount = 1
    private var lastLeftClick = Date.distantPast
    private var lastPostedLocation: CGPoint?
    private var capturedFrame = CGRect.zero

    func apply(_ message: WireMessage, displayFrame: CGRect = .zero) {
        capturedFrame = displayFrame
        guard AccessibilityGate.isTrusted(prompt: false) else { return }
        switch message {
        case .pointer(let dx, let dy):
            move(dx: dx, dy: dy)
        case .cursor(let x, let y):
            moveAbsolute(x: x, y: y, displayFrame: displayFrame)
        case .button(let button, let phase):
            setButton(button, phase: phase)
        case .scroll(let dx, let dy):
            scroll(dx: dx, dy: dy)
        case .key(let keyCode, let phase, let modifiers):
            postKey(code: keyCode, phase: phase, modifiers: modifiers)
        case .text(let text):
            postText(text)
        case .media(let action):
            applyMedia(action)
        case .hello, .pair, .paired, .needCode, .rejected, .ping, .pong, .videoHello, .screenUnavailable, .quality, .displays, .screen, .audio:
            break
        }
    }

    func moveAbsolute(x: Double, y: Double, displayFrame: CGRect) {
        guard AccessibilityGate.isTrusted(prompt: false), displayFrame.width > 0, displayFrame.height > 0 else { return }
        let location = ScreenMapping.globalPoint(normalizedX: x, normalizedY: y, displayFrame: displayFrame)
        postMove(to: location, deltaX: 0, deltaY: 0)
    }

    private func move(dx: Double, dy: Double) {
        let scaled = PointerGain.cursorDelta(dx: dx, dy: dy)
        var location = cursorLocation()
        location.x += scaled.dx
        location.y += scaled.dy
        postMove(to: location, deltaX: Int64(scaled.dx.rounded()), deltaY: Int64(scaled.dy.rounded()))
    }

    private func postMove(to location: CGPoint, deltaX: Int64, deltaY: Int64) {
        lastPostedLocation = location
        let type: CGEventType
        let button: CGMouseButton
        if leftIsDown {
            type = .leftMouseDragged
            button = .left
        } else if rightIsDown {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        event.post(tap: .cghidEventTap)
    }

    private func setButton(_ button: MouseButton, phase: ButtonPhase) {
        let location = lastPostedLocation ?? cursorLocation()
        if phase == .up {
            // Soltar en el mismo turno reentra en AppKit y tumba la sesión.
            Task { @MainActor [weak self] in
                self?.postButton(button, phase: .up, at: location)
            }
            return
        }
        postButton(button, phase: .down, at: location)
    }

    private func postButton(_ button: MouseButton, phase: ButtonPhase, at location: CGPoint) {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch (button, phase) {
        case (.left, .down):
            type = .leftMouseDown
            cgButton = .left
            leftIsDown = true
            noteLeftClick()
        case (.left, .up):
            type = .leftMouseUp
            cgButton = .left
            leftIsDown = false
        case (.right, .down):
            type = .rightMouseDown
            cgButton = .right
            rightIsDown = true
        case (.right, .up):
            type = .rightMouseUp
            cgButton = .right
            rightIsDown = false
        }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ) else { return }
        if button == .left {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(leftClickCount))
        }
        event.post(tap: .cghidEventTap)
    }

    private func noteLeftClick() {
        let now = Date()
        if now.timeIntervalSince(lastLeftClick) < 0.35 {
            leftClickCount += 1
        } else {
            leftClickCount = 1
        }
        lastLeftClick = now
    }

    /// Dedo hacia arriba (dy negativo en UIKit) produce un wheel positivo.
    private func scroll(dx: Double, dy: Double) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: clampWheel(-dy),
            wheel2: clampWheel(-dx),
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postKey(code: UInt16, phase: ButtonPhase, modifiers: KeyModifiers) {
        if modifiers == .control && SpaceChord.isDesktopArrow(code) {
            if phase == .down {
                postSpaceChord(code)
            }
            return
        }
        guard let event = CGEvent(
            keyboardEventSource: keyboardSource,
            virtualKey: CGKeyCode(code),
            keyDown: phase == .down
        ) else { return }
        event.flags = flags(modifiers)
        event.post(tap: .cghidEventTap)
    }

    /// Anterior, Ventanas y Siguiente. No se manda la flecha: en este macOS la
    /// recibe la app de delante y el escritorio no se mueve.
    private func postSpaceChord(_ arrow: UInt16) {
        let frame = capturedFrame
        chordQueue.async {
            DesktopMotion.perform(arrow: arrow, frame: frame)
        }
    }

    private func postText(_ text: String) {
        let characters = Array(text.utf16)
        guard !characters.isEmpty else { return }
        characters.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func applyMedia(_ action: MediaAction) {
        switch action {
        case .volumeUp:
            VolumeController.change(by: 0.0625)
        case .volumeDown:
            VolumeController.change(by: -0.0625)
        case .mute:
            VolumeController.toggleMute()
        case .playPause:
            postSystemKey(16)
        case .next:
            postSystemKey(17)
        case .previous:
            postSystemKey(18)
        }
    }

    private func postSystemKey(_ key: Int32) {
        postSystemKey(key, pressed: true)
        postSystemKey(key, pressed: false)
    }

    private func postSystemKey(_ key: Int32, pressed: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: pressed ? 0xa00 : 0xb00)
        let data1 = Int((key << 16) | ((pressed ? 0xa : 0xb) << 8))
        NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func flags(_ modifiers: KeyModifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    private func cursorLocation() -> CGPoint {
        CGEvent(source: source)?.location ?? .zero
    }

    private func clampWheel(_ value: Double) -> Int32 {
        Int32(max(-2_000, min(2_000, value.rounded())))
    }
}
