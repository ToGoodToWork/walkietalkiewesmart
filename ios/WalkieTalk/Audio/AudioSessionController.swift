import AVFoundation

/// Centralized AVAudioSession configuration for voice calls.
/// Per spec §6: `.playAndRecord` / `.voiceChat` / allow Bluetooth / default to speaker.
@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()

    private(set) var isActive = false
    private(set) var isSpeakerOn = true

    private init() {}

    func activateForVoice() throws {
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
        try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
    }

    func setSpeaker(on: Bool) throws {
        isSpeakerOn = on
        guard isActive else { return }
        try AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
    }

    var currentRouteName: String {
        let route = AVAudioSession.sharedInstance().currentRoute
        if let port = route.outputs.first { return port.portName }
        return "Unknown"
    }
}
