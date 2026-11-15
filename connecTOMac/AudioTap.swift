import AVFoundation
import CoreMedia
import Foundation

/// Pasa el audio del sistema, en el formato que entregue ScreenCaptureKit, a PCM de 16 bits.
nonisolated final class AudioTap: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var sourceKey: FormatKey?
    private let lock = NSLock()

    func reset() {
        lock.lock()
        converter = nil
        sourceKey = nil
        lock.unlock()
    }

    func convert(_ sampleBuffer: CMSampleBuffer) -> (rate: Int, channels: Int, pcm: Data)? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let source = AVAudioFormat(cmAudioFormatDescription: description)
        guard source.sampleRate > 0,
              source.channelCount > 0,
              let input = copy(sampleBuffer, format: source) else {
            return nil
        }
        let key = FormatKey(sampleRate: source.sampleRate, channels: source.channelCount, format: source.commonFormat)
        lock.lock()
        let converter = preparedConverter(for: source, key: key)
        let output = converter?.outputFormat
        lock.unlock()
        guard let converter, let output else { return nil }

        let ratio = output.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        guard let rendered = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: max(capacity, 1)) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: rendered, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, rendered.frameLength > 0 else { return nil }
        let buffers = rendered.audioBufferList.pointee.mBuffers
        guard let pointer = buffers.mData, buffers.mDataByteSize > 0 else { return nil }
        let pcm = Data(bytes: pointer, count: Int(buffers.mDataByteSize))
        return (Int(output.sampleRate.rounded()), Int(output.channelCount), pcm)
    }

    private func preparedConverter(for source: AVAudioFormat, key: FormatKey) -> AVAudioConverter? {
        if let converter, sourceKey == key { return converter }
        guard let output = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: source.sampleRate,
            channels: source.channelCount,
            interleaved: true
        ), let converter = AVAudioConverter(from: source, to: output) else {
            return nil
        }
        self.converter = converter
        sourceKey = key
        return converter
    }

    private func copy(_ sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}

nonisolated private struct FormatKey: Equatable {
    var sampleRate: Double
    var channels: AVAudioChannelCount
    var format: AVAudioCommonFormat
}
