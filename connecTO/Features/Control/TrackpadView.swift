import SwiftUI
import UIKit

struct TrackpadView: View {
    var dragArmed: Bool
    var clickArmed: Bool
    var onMove: (Double, Double) -> Void
    var onScroll: (Double, Double) -> Void
    var onLeftDown: () -> Void
    var onLeftUp: () -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void

    var body: some View {
        TrackpadRepresentable(
            dragArmed: dragArmed,
            clickArmed: clickArmed,
            onMove: onMove,
            onScroll: onScroll,
            onLeftDown: onLeftDown,
            onLeftUp: onLeftUp,
            onLeftClick: onLeftClick,
            onRightClick: onRightClick
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            Text("Desliza para mover el cursor")
                .font(.callout)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
    }
}

private struct TrackpadRepresentable: UIViewRepresentable {
    var dragArmed: Bool
    var clickArmed: Bool
    var onMove: (Double, Double) -> Void
    var onScroll: (Double, Double) -> Void
    var onLeftDown: () -> Void
    var onLeftUp: () -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void

    func makeUIView(context: Context) -> TrackpadCanvas {
        TrackpadCanvas()
    }

    func updateUIView(_ view: TrackpadCanvas, context: Context) {
        view.dragArmed = dragArmed
        view.clickArmed = clickArmed
        view.onMove = onMove
        view.onScroll = onScroll
        view.onLeftDown = onLeftDown
        view.onLeftUp = onLeftUp
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
    }
}

final class TrackpadCanvas: UIView {
    var dragArmed = false
    var clickArmed = false
    var onMove: (Double, Double) -> Void = { _, _ in }
    var onScroll: (Double, Double) -> Void = { _, _ in }
    var onLeftDown: () -> Void = {}
    var onLeftUp: () -> Void = {}
    var onLeftClick: () -> Void = {}
    var onRightClick: () -> Void = {}

    private var lastLocation: [ObjectIdentifier: CGPoint] = [:]
    private var travel: CGFloat = 0
    private var usedTwoFingers = false
    private var holdingDrag = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            lastLocation[ObjectIdentifier(touch)] = touch.location(in: self)
        }
        if activeCount(event) >= 2 {
            usedTwoFingers = true
            releaseDrag()
            return
        }
        if dragArmed, !usedTwoFingers, !holdingDrag, activeCount(event) == 1 {
            holdingDrag = true
            onLeftDown()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeCount(event) >= 2 {
            usedTwoFingers = true
            releaseDrag()
            sendScroll(for: touches)
            return
        }
        guard !usedTwoFingers else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let location = touch.location(in: self)
            guard let previous = lastLocation[key] else {
                lastLocation[key] = location
                continue
            }
            let dx = location.x - previous.x
            let dy = location.y - previous.y
            lastLocation[key] = location
            travel += hypot(dx, dy)
            if dx != 0 || dy != 0 {
                onMove(Double(dx), Double(dy))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        clear(touches)
        finishIfIdle(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clear(touches)
        releaseDrag()
        resetGesture()
    }

    private func sendScroll(for touches: Set<UITouch>) {
        var dx = 0.0
        var dy = 0.0
        var samples = 0
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let location = touch.location(in: self)
            if let previous = lastLocation[key] {
                let stepX = location.x - previous.x
                let stepY = location.y - previous.y
                dx += stepX
                dy += stepY
                samples += 1
                travel += hypot(stepX, stepY)
            }
            lastLocation[key] = location
        }
        guard samples > 0 else { return }
        onScroll(dx / Double(samples), dy / Double(samples))
    }

    private func finishIfIdle(_ event: UIEvent?) {
        guard activeCount(event) == 0 else { return }
        if holdingDrag {
            releaseDrag()
        } else if travel < 8, clickArmed, !usedTwoFingers {
            onLeftClick()
        }
        resetGesture()
    }

    private func releaseDrag() {
        guard holdingDrag else { return }
        holdingDrag = false
        onLeftUp()
    }

    private func resetGesture() {
        lastLocation.removeAll()
        travel = 0
        usedTwoFingers = false
    }

    private func clear(_ touches: Set<UITouch>) {
        for touch in touches {
            lastLocation.removeValue(forKey: ObjectIdentifier(touch))
        }
    }

    private func activeCount(_ event: UIEvent?) -> Int {
        event?.allTouches?.filter { touch in
            switch touch.phase {
            case .ended, .cancelled:
                return false
            default:
                return true
            }
        }.count ?? 0
    }
}
