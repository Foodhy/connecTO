import CoreGraphics

/// Convierte un toque en la vista del iPad a un punto de la imagen, y ese punto a la pantalla del Mac.
/// La imagen cabe entera: si la vista es más ancha, sobran bandas a los lados.
nonisolated enum ScreenMapping {
    static func normalizedPoint(touch: CGPoint, viewSize: CGSize, videoSize: CGSize) -> (x: Double, y: Double)? {
        guard let frame = fittedFrame(viewSize: viewSize, videoSize: videoSize) else { return nil }
        return normalizedPoint(touch: touch, contentFrame: frame)
    }

    /// El rectángulo donde cabe la imagen entera, con bandas si la vista no tiene la misma proporción.
    static func fittedFrame(viewSize: CGSize, videoSize: CGSize) -> CGRect? {
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
        return CGRect(
            x: (viewSize.width - fitted.width) / 2,
            y: (viewSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// `contentFrame` es la imagen ya ampliada. Un toque fuera de ella no mueve el cursor.
    static func normalizedPoint(touch: CGPoint, contentFrame: CGRect) -> (x: Double, y: Double)? {
        guard contentFrame.width > 0, contentFrame.height > 0 else { return nil }
        let localX = touch.x - contentFrame.origin.x
        let localY = touch.y - contentFrame.origin.y
        guard localX >= 0, localY >= 0, localX <= contentFrame.width, localY <= contentFrame.height else {
            return nil
        }
        return (Double(localX / contentFrame.width), Double(localY / contentFrame.height))
    }

    static func zoomedFrame(fitted: CGRect, zoom: CGFloat, origin: CGPoint) -> CGRect {
        CGRect(x: origin.x, y: origin.y, width: fitted.width * zoom, height: fitted.height * zoom)
    }

    /// La imagen ampliada no se sale de la vista. Si aún cabe, se queda centrada.
    static func clampZoomOrigin(origin: CGPoint, contentSize: CGSize, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: clampZoomAxis(origin.x, content: contentSize.width, view: viewSize.width),
            y: clampZoomAxis(origin.y, content: contentSize.height, view: viewSize.height)
        )
    }

    static func clampZoomAxis(_ origin: CGFloat, content: CGFloat, view: CGFloat) -> CGFloat {
        guard content > 0, view > 0 else { return origin }
        if content <= view {
            return (view - content) / 2
        }
        return min(0, max(view - content, origin))
    }

    /// `displayFrame` usa el origen arriba a la izquierda, el mismo de `CGEvent`.
    static func globalPoint(normalizedX: Double, normalizedY: Double, displayFrame: CGRect) -> CGPoint {
        CGPoint(
            x: displayFrame.origin.x + CGFloat(normalizedX) * displayFrame.width,
            y: displayFrame.origin.y + CGFloat(normalizedY) * displayFrame.height
        )
    }
}
