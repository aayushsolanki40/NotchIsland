import AudioToolbox
import CoreAudio
import Foundation

/// Watches the default output device's volume and mute state.
final class VolumeService: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var muted = false

    var onChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read(notify: true) }
    private var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                           mScope: kAudioDevicePropertyScopeOutput,
                                                           mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                         mScope: kAudioDevicePropertyScopeOutput,
                                                         mElement: kAudioObjectPropertyElementMain)

    var symbol: String {
        if muted || level < 0.01 { return "speaker.slash.fill" }
        return level < 0.33 ? "speaker.wave.1.fill" : level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    func start() {
        var defaultDevice = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, deviceListener)
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, deviceListener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, .main, deviceListener)
        // Switching outputs (e.g. to AirPods) shouldn't flash the volume HUD.
        read(notify: false)
    }

    private func read(notify: Bool) {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else { return }
        var mute: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mute) != noErr { mute = 0 }

        let changed = abs(volume - level) > 0.001 || (mute != 0) != muted
        level = volume
        muted = mute != 0
        if notify && changed { onChange?() }
    }
}
