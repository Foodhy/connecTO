import CoreGraphics
import Testing
@testable import connecTO

struct ScreenMappingTests {
    @Test func centerOfAMatchingViewIsTheMiddleOfThePicture() {
        let point = ScreenMapping.normalizedPoint(
            touch: CGPoint(x: 50, y: 25),
            viewSize: CGSize(width: 100, height: 50),
            videoSize: CGSize(width: 200, height: 100)
        )
        #expect(point?.x == 0.5)
        #expect(point?.y == 0.5)
    }

    @Test func cornersOfThePictureStayAtTheCorners() {
        let topLeft = ScreenMapping.normalizedPoint(
            touch: CGPoint(x: 0, y: 25),
            viewSize: CGSize(width: 100, height: 100),
            videoSize: CGSize(width: 200, height: 100)
        )
        let bottomRight = ScreenMapping.normalizedPoint(
            touch: CGPoint(x: 100, y: 75),
            viewSize: CGSize(width: 100, height: 100),
            videoSize: CGSize(width: 200, height: 100)
        )
        #expect(topLeft?.x == 0)
        #expect(topLeft?.y == 0)
        #expect(bottomRight?.x == 1)
        #expect(bottomRight?.y == 1)
    }

    @Test func aTouchInTheLetterboxIsIgnored() {
        let point = ScreenMapping.normalizedPoint(
            touch: CGPoint(x: 50, y: 10),
            viewSize: CGSize(width: 100, height: 100),
            videoSize: CGSize(width: 200, height: 100)
        )
        #expect(point == nil)
    }

    @Test func normalizedPointLandsOnTheDisplay() {
        let frame = CGRect(x: 100, y: 200, width: 1000, height: 500)
        #expect(ScreenMapping.globalPoint(normalizedX: 0, normalizedY: 0, displayFrame: frame) == CGPoint(x: 100, y: 200))
        #expect(ScreenMapping.globalPoint(normalizedX: 1, normalizedY: 1, displayFrame: frame) == CGPoint(x: 1100, y: 700))
        #expect(ScreenMapping.globalPoint(normalizedX: 0.5, normalizedY: 0.5, displayFrame: frame) == CGPoint(x: 600, y: 450))
    }
}
