import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Un monitor que macOS añade mientras el objeto vive. Soltarlo lo quita.
final class VirtualDisplay {
    static let pixelWidth: UInt32 = 2048
    static let pixelHeight: UInt32 = 1536
    static let refreshRate: Double = 60
    static let hiDPI: UInt32 = 1

    let displayID: UInt32
    private let display: CGVirtualDisplay

    init?() {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "connecTO"
        descriptor.vendorID = 0x1000
        descriptor.productID = 0x2000
        descriptor.serialNum = 0x3000
        descriptor.maxPixelsWide = Self.pixelWidth
        descriptor.maxPixelsHigh = Self.pixelHeight
        descriptor.sizeInMillimeters = CGSize(width: 280, height: 210)
        descriptor.setDispatchQueue(DispatchQueue.main)

        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return nil }
        let mode = CGVirtualDisplayMode(
            width: Self.pixelWidth,
            height: Self.pixelHeight,
            refreshRate: Self.refreshRate
        )
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = Self.hiDPI
        settings.modes = [mode]
        guard display.apply(settings), display.displayID != 0 else { return nil }
        self.display = display
        displayID = display.displayID
    }

    /// El id ya está entre los displays que ScreenCaptureKit puede capturar.
    func waitUntilListed() async -> Bool {
        for _ in 0..<25 {
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
               content.displays.contains(where: { $0.displayID == displayID }) {
                placeToTheRightOfMain()
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// El cursor del Mac entra por el borde derecho de la pantalla principal.
    private func placeToTheRightOfMain() {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let result = CGConfigureDisplayOrigin(
            config,
            displayID,
            Int32(bounds.maxX.rounded()),
            Int32(bounds.minY.rounded())
        )
        if result == .success {
            CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            CGCancelDisplayConfiguration(config)
        }
    }
}
