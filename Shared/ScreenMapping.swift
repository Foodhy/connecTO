import CoreGraphics

/// Convierte un toque en la vista del iPad a un punto de la imagen, y ese punto a la pantalla del Mac.
/// La imagen cabe entera: si la vista es más ancha, sobran bandas a los lados.
nonisolated enum ScreenMapping {
    static func normalizedPoint(touch: CGPoint, viewSize: CGSize, videoSize: CGSize) -> (x: Double, y: Double)? {
        guard videoSize.width > 0, videoSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let videoAspect = videoSize.width / videoSize.height
        let viewAspect = viewSize.width / viewSize.height
        let fitted: CGSize
        if videoAspect > viewAspect {
            fitted = CGSize(width: viewSize.width, height: viewSize.width / videoAspect)
        } else {
            fitted = CGSize(width: viewSize.height * videoAspect, height: viewSize.height)
        }
        let originX = (viewSize.width - fitted.width) / 2
        let originY = (viewSize.height - fitted.height) / 2
        let localX = touch.x - originX
        let localY = touch.y - originY
        guard localX >= 0, localY >= 0, localX <= fitted.width, localY <= fitted.height else {
            return nil
        }
        return (Double(localX / fitted.width), Double(localY / fitted.height))
    }

    /// `displayFrame` usa el origen arriba a la izquierda, el mismo de `CGEvent`.
    static func globalPoint(normalizedX: Double, normalizedY: Double, displayFrame: CGRect) -> CGPoint {
        CGPoint(
            x: displayFrame.origin.x + CGFloat(normalizedX) * displayFrame.width,
            y: displayFrame.origin.y + CGFloat(normalizedY) * displayFrame.height
        )
    }
}
