import AVFoundation
import Foundation

/// Reproduce el PCM que manda el Mac. El formato es 16 bits intercalado.
final class SystemAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var playing = false

    func prepare(sampleRate: Int, channels: Int) {
        guard sampleRate > 0, channels > 0 else { return }
        let rate = Double(sampleRate)
        let count = AVAudioChannelCount(channels)
        if playing, let format, format.sampleRate == rate, format.channelCount == count { return }
        stop()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: rate,
            channels: count,
            interleaved: true
        ) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
        } catch {
            engine.stop()
            if engine.attachedNodes.contains(player) {
                engine.detach(player)
            }
            return
        }
        self.format = format
        player.play()
        playing = true
    }

    func play(_ data: Data) {
        guard playing, let format else { return }
        let frameBytes = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard frameBytes > 0 else { return }
        let frames = AVAudioFrameCount(data.count / frameBytes)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let byteCount = Int(frames) * frameBytes
        guard let destination = buffer.audioBufferList.pointee.mBuffers.mData else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            destination.copyMemory(from: base, byteCount: byteCount)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        guard playing || format != nil else { return }
        player.stop()
        engine.stop()
        if engine.attachedNodes.contains(player) {
            engine.detach(player)
        }
        format = nil
        playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
