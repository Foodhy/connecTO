import AppKit
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import VideoToolbox

nonisolated final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPacket: @Sendable (VideoPacket) -> Void = { _ in }
    var onFailure: @Sendable () -> Void = {}

    private let queue = DispatchQueue(label: "connecTO.capture")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var session: VTCompressionSession?
    private var formatSent = false
    private var frameCount = 0
    private var outputWidth = 0
    private var outputHeight = 0
    private var frameStorage = CGRect.zero
    private var running = false
    private var startToken = 0
    private var wantsAudio = false
    private var audioFormatSent = false
    private let audioQueue = DispatchQueue(label: "connecTO.audio")
    private let audioTap = AudioTap()

    func start(longSide: Int, displayID: UInt32?, captureAudio: Bool) async throws -> CaptureStart {
        stop()
        startToken += 1
        let token = startToken
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard token == startToken else { throw CaptureError.replaced }
        let names = await MainActor.run { ScreenCapturer.displayNames() }
        let displays = Self.sharedDisplays(from: content.displays, names: names)
        let mainID = CGMainDisplayID()
        guard let chosenID = DisplayList.resolvedID(preferred: displayID, displays: displays, mainID: mainID),
              let display = content.displays.first(where: { $0.displayID == chosenID }) else {
            throw CaptureError.noDisplay
        }
        let nativeLong = Double(max(display.width, display.height))
        let requested = min(nativeLong, Double(max(longSide, 960)))
        let scale = min(1.0, requested / nativeLong)
        let width = even(Int((Double(display.width) * scale).rounded()))
        let height = even(Int((Double(display.height) * scale).rounded()))
        let displayFrame = CGDisplayBounds(display.displayID)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 4
        configuration.scalesToFit = true
        if captureAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        let compression = try makeSession(width: width, height: height)
        guard token == startToken else {
            VTCompressionSessionInvalidate(compression)
            throw CaptureError.replaced
        }
        stateLock.lock()
        session = compression
        formatSent = false
        frameCount = 0
        outputWidth = width
        outputHeight = height
        frameStorage = displayFrame
        wantsAudio = captureAudio
        audioFormatSent = false
        running = true
        stateLock.unlock()
        audioTap.reset()

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: queue)
        var audioStarted = false
        if captureAudio {
            do {
                try stream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: audioQueue)
                audioStarted = true
            } catch {
                audioStarted = false
            }
        }
        try await stream.startCapture()
        guard token == startToken else {
            let stale = stream
            Task { try? await stale.stopCapture() }
            throw CaptureError.replaced
        }
        self.stream = stream
        return CaptureStart(frame: displayFrame, displayID: display.displayID, audio: audioStarted, displays: displays)
    }

    func stop() {
        startToken += 1
        stateLock.lock()
        running = false
        let compression = session
        session = nil
        let activeStream = stream
        stream = nil
        stateLock.unlock()
        activeStream?.stopCapture()
        if let compression {
            VTCompressionSessionInvalidate(compression)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            emitScreen(sampleBuffer)
        case .audio:
            emitAudio(sampleBuffer)
        default:
            break
        }
    }

    private func emitScreen(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let compression = currentSession() else { return }
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var flags = VTEncodeInfoFlags()
        let properties = forceKeyFrame() ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(
            compression,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentation,
            duration: .invalid,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }

    private func emitAudio(_ sampleBuffer: CMSampleBuffer) {
        stateLock.lock()
        let active = running && wantsAudio
        let needsFormat = !audioFormatSent
        stateLock.unlock()
        guard active, let converted = audioTap.convert(sampleBuffer) else { return }
        if needsFormat {
            stateLock.lock()
            audioFormatSent = true
            stateLock.unlock()
            onPacket(.audioFormat(sampleRate: converted.rate, channels: converted.channels))
        }
        onPacket(.audio(data: converted.pcm))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure()
    }

    private func makeSession(width: Int, height: Int) throws -> VTCompressionSession {
        var compression: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, status, _, sampleBuffer in
                guard status == noErr, let sampleBuffer, let refcon else { return }
                let capturer = Unmanaged<ScreenCapturer>.fromOpaque(refcon).takeUnretainedValue()
                capturer.emit(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compression
        )
        guard status == noErr, let compression else { throw CaptureError.encoder }
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: Self.bitRate(width: width, height: height)))
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 30))
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 60))
        VTCompressionSessionPrepareToEncodeFrames(compression)
        return compression
    }

    private func emit(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if !formatSent, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let sets = parameterSets(from: format)
            if !sets.isEmpty {
                formatSent = true
                onPacket(.format(parameterSets: sets, width: outputWidth, height: outputHeight))
            }
        }
        guard formatSent, let data = sampleData(sampleBuffer) else { return }
        onPacket(.sample(isKeyframe: isKeyframe(sampleBuffer), data: data))
    }

    private func currentSession() -> VTCompressionSession? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return session
    }

    private func forceKeyFrame() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        frameCount += 1
        return frameCount == 1 || frameCount % 60 == 0
    }

    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as NSArray?,
              let dictionary = attachments.firstObject as? NSDictionary,
              let notSync = dictionary[kCMSampleAttachmentKey_NotSync] as? Bool else {
            return true
        }
        return !notSync
    }

    private func parameterSets(from format: CMFormatDescription) -> [Data] {
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil
        )
        var sets: [Data] = []
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            if status == noErr, let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        return sets
    }

    private func sampleData(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer else {
            return nil
        }
        return Data(bytes: pointer, count: length)
    }

    private func even(_ value: Int) -> Int {
        let rounded = value & ~1
        return max(2, rounded)
    }
}

nonisolated struct CaptureStart: Equatable, Sendable {
    var frame: CGRect
    var displayID: UInt32
    var audio: Bool
    var displays: [SharedDisplay]
}

enum CaptureError: Error {
    case noDisplay
    case encoder
    case replaced
}

extension ScreenCapturer {
    fileprivate static func sharedDisplays(
        from displays: [SCDisplay],
        names: [CGDirectDisplayID: String]
    ) -> [SharedDisplay] {
        let listed = displays.map { display in
            SharedDisplay(
                id: display.displayID,
                name: names[display.displayID] ?? "Pantalla",
                width: display.width,
                height: display.height
            )
        }
        return DisplayList.ordered(listed, mainID: CGMainDisplayID())
    }

    @MainActor
    private static func displayNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen) else { continue }
            let name = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            names[id] = name.isEmpty ? "Pantalla" : name
        }
        return names
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        switch screen.deviceDescription[key] {
        case let number as NSNumber:
            return number.uint32Value
        default:
            return nil
        }
    }
}

extension ScreenCapturer {
    static func bitRate(width: Int, height: Int) -> Int {
        let pixels = max(width * height, 1)
        let scaled = 5_000_000 * pixels / (1280 * 720)
        return min(20_000_000, max(2_000_000, scaled))
    }
}
