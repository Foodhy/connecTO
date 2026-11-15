import CoreAudio
import Foundation

enum VolumeController {
    static func change(by delta: Float32) {
        let device = defaultOutputDevice()
        guard device != 0 else { return }
        var address = volumeAddress
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return }
        volume = min(1, max(0, volume + delta))
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
    }

    static func toggleMute() {
        setMuted(!isMuted())
    }

    static func isMuted() -> Bool {
        var mute = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress
        guard AudioObjectGetPropertyData(defaultOutputDevice(), &address, 0, nil, &size, &mute) == noErr else { return false }
        return mute != 0
    }

    static func setMuted(_ muted: Bool) {
        let device = defaultOutputDevice()
        guard device != 0 else { return }
        var address = muteAddress
        var mute: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &mute)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x766D7663), // 'vmvc', volumen principal virtual
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return deviceID
    }
}
