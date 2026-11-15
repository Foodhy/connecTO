import Foundation

/// Curva del cursor: un dedo lento mueve poco, un dedo rápido mueve más.
/// `dx`/`dy` entran en puntos del trackpad y salen en puntos del cursor.
nonisolated enum PointerGain {
    static func cursorDelta(dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        let distance = (dx * dx + dy * dy).squareRoot()
        let gain = 1.0 + min(distance, 40) / 20
        return (dx * gain, dy * gain)
    }
}
