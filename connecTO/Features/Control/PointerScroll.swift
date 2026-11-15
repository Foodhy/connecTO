import UIKit

/// El Magic Mouse no manda dos dedos: manda un scroll sin toques.
enum PointerScroll {
    static func recognizer(target: Any, action: Selector) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer(target: target, action: action)
        pan.allowedScrollTypesMask = .all
        pan.minimumNumberOfTouches = 0
        pan.maximumNumberOfTouches = 0
        pan.cancelsTouchesInView = false
        return pan
    }
}
