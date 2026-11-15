import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

struct DesktopView: View {
    var client: SessionClient
    var dragArmed: Bool
    var clickArmed: Bool

    var body: some View {
        DesktopRepresentable(client: client, dragArmed: dragArmed, clickArmed: clickArmed)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DesktopRepresentable: UIViewRepresentable {
    var client: SessionClient
    var dragArmed: Bool
    var clickArmed: Bool

    func makeUIView(context: Context) -> DesktopCanvas {
        DesktopCanvas()
    }

    func updateUIView(_ view: DesktopCanvas, context: Context) {
        view.videoSize = client.videoSize
        view.dragArmed = dragArmed
        view.clickArmed = clickArmed
        view.onCursor = { client.moveCursor(x: $0, y: $1) }
        view.onLeftDown = { client.sendControl(.button(.left, .down)) }
        view.onLeftUp = { client.sendControl(.button(.left, .up)) }
        view.onLeftClick = { client.click(.left) }
        view.onScroll = { client.scroll(dx: $0, dy: $1) }
        view.onKey = { client.sendControl(.key(keyCode: $0, phase: $1, modifiers: $2)) }
        client.attachDisplay { [weak view] packet in
            view?.player.enqueue(packet)
        }
    }
}

final class DesktopCanvas: UIView {
    var videoSize = CGSize.zero
    var onCursor: (Double, Double) -> Void = { _, _ in }
    var dragArmed = false
    var clickArmed = false
    var onLeftDown: () -> Void = {}
    var onLeftUp: () -> Void = {}
    var onLeftClick: () -> Void = {}
    var onScroll: (Double, Double) -> Void = { _, _ in }
    var onKey: (UInt16, ButtonPhase, KeyModifiers) -> Void = { _, _, _ in }
    let player = H264Display()

    private var lastLocation: [ObjectIdentifier: CGPoint] = [:]
    private var travel: CGFloat = 0
    private var usedTwoFingers = false
    private var holding = false

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        player.displayLayer.frame = bounds
        layer.addSublayer(player.displayLayer)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(pointerMoved(_:)))
        addGestureRecognizer(hover)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        player.displayLayer.frame = bounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        becomeFirstResponder()
        for touch in touches {
            lastLocation[ObjectIdentifier(touch)] = touch.location(in: self)
        }
        if fingerCount(event) >= 2 {
            usedTwoFingers = true
            releaseHold()
            return
        }
        guard let touch = touches.first else { return }
        moveCursor(to: touch.location(in: self))
        if !isPointer(touch), dragArmed {
            pressLeft()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if fingerCount(event) >= 2 {
            usedTwoFingers = true
            releaseHold()
            sendScroll(touches.filter { !isPointer($0) })
            return
        }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let key = ObjectIdentifier(touch)
        if let previous = lastLocation[key] {
            travel += hypot(location.x - previous.x, location.y - previous.y)
        }
        lastLocation[key] = location
        guard !isPointer(touch) else {
            moveCursor(to: location)
            return
        }
        guard !usedTwoFingers else { return }
        moveCursor(to: location)
        if dragArmed {
            pressLeft()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first?.location(in: self)
        clear(touches)
        guard fingerCount(event) == 0 else { return }
        let tapped = travel < 12 && !usedTwoFingers
        if holding {
            releaseHold()
        } else if tapped, clickArmed {
            if let location {
                moveCursor(to: location)
            }
            onLeftClick()
        } else if let location, !usedTwoFingers {
            moveCursor(to: location)
        }
        resetGesture()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clear(touches)
        releaseHold()
        resetGesture()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard forward(presses, phase: .down) else {
            super.pressesBegan(presses, with: event)
            return
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard forward(presses, phase: .up) else {
            super.pressesEnded(presses, with: event)
            return
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard forward(presses, phase: .up) else {
            super.pressesCancelled(presses, with: event)
            return
        }
    }

    @objc private func pointerMoved(_ gesture: UIHoverGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        moveCursor(to: gesture.location(in: self))
    }

    private func normalized(_ location: CGPoint) -> (x: Double, y: Double)? {
        ScreenMapping.normalizedPoint(touch: location, viewSize: bounds.size, videoSize: videoSize)
    }

    private func moveCursor(to location: CGPoint) {
        guard let point = normalized(location) else { return }
        onCursor(point.x, point.y)
    }

    private func pressLeft() {
        guard !holding else { return }
        holding = true
        onLeftDown()
    }

    private func sendScroll(_ touches: [UITouch]) {
        var dx = 0.0
        var dy = 0.0
        var samples = 0
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let location = touch.location(in: self)
            if let previous = lastLocation[key] {
                dx += location.x - previous.x
                dy += location.y - previous.y
                samples += 1
            }
            lastLocation[key] = location
        }
        guard samples > 0 else { return }
        onScroll(dx / Double(samples), dy / Double(samples))
    }

    private func releaseHold() {
        guard holding else { return }
        holding = false
        onLeftUp()
    }

    private func resetGesture() {
        lastLocation.removeAll()
        travel = 0
        usedTwoFingers = false
    }

    private func isPointer(_ touch: UITouch) -> Bool {
        touch.type == .indirectPointer || touch.type == .indirect
    }

    private func forward(_ presses: Set<UIPress>, phase: ButtonPhase) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            guard let code = HardwareKeyCode.macKeyCode(hidUsage: key.keyCode.rawValue) else { continue }
            onKey(code, phase, Self.modifiers(key.modifierFlags))
            handled = true
        }
        return handled
    }

    private static func modifiers(_ flags: UIKeyModifierFlags) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    private func clear(_ touches: Set<UITouch>) {
        for touch in touches {
            lastLocation.removeValue(forKey: ObjectIdentifier(touch))
        }
    }

    private func fingerCount(_ event: UIEvent?) -> Int {
        event?.allTouches?.filter { touch in
            guard !isPointer(touch) else { return false }
            switch touch.phase {
            case .ended, .cancelled:
                return false
            default:
                return true
            }
        }.count ?? 0
    }
}

final class H264Display {
    let displayLayer = AVSampleBufferDisplayLayer()
    private var format: CMFormatDescription?
    private var timestamp = CMTime.zero

    init() {
        displayLayer.videoGravity = .resizeAspect
    }

    func enqueue(_ packet: VideoPacket) {
        switch packet {
        case .format(let sets, _, _):
            format = makeFormat(sets)
            displayLayer.sampleBufferRenderer.flush()
            timestamp = .zero
        case .sample(let isKeyframe, let data):
            guard let format, let sample = makeSample(data: data, format: format, keyframe: isKeyframe) else { return }
            if displayLayer.sampleBufferRenderer.status == .failed {
                displayLayer.sampleBufferRenderer.flush()
            }
            displayLayer.sampleBufferRenderer.enqueue(sample)
        }
    }

    private func makeFormat(_ sets: [Data]) -> CMFormatDescription? {
        guard !sets.isEmpty else { return nil }
        let buffers = sets.map { $0 as NSData }
        let pointers = buffers.map { UnsafePointer<UInt8>($0.bytes.bindMemory(to: UInt8.self, capacity: $0.length)) }
        let sizes = buffers.map(\.length)
        var description: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: buffers.count,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            }
        }
        return status == noErr ? description : nil
    }

    private func makeSample(data: Data, format: CMFormatDescription, keyframe: Bool) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        let length = data.count
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: length
            )
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        timestamp = CMTimeAdd(timestamp, CMTime(value: 1, timescale: 30))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var sampleSize = length
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
           let dictionary = attachments.firstObject as? NSMutableDictionary {
            dictionary[kCMSampleAttachmentKey_NotSync] = !keyframe
            dictionary[kCMSampleAttachmentKey_DependsOnOthers] = !keyframe
        }
        return sample
    }
}
