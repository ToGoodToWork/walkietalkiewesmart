import Foundation
import Observation
import LiveKit

/// One LiveKit Room. Owns its lifecycle, exposes UI-relevant state to SwiftUI.
@MainActor
@Observable
final class RoomController {
    enum Phase: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// True while the local mic publish track is unmuted (audio actually flowing out).
    private(set) var isTransmitting = false
    /// User toggled "self-mute" — overrides PTT; mic stays muted even on press.
    var isSelfMuted = false
    /// Current audio output route name (e.g. "Speaker", "iPhone", "AirPods Pro").
    private(set) var routeName: String = "Speaker"
    /// Latching "lock to talk" — transmission stays on across PTT releases until toggled off.
    var isLocked = false

    private let room = Room()
    private var currentChannel: Channel?

    // MARK: - Lifecycle

    func markFailed(_ message: String) {
        phase = .failed(message)
    }

    func connect(to channel: Channel, token: JoinToken) async {
        phase = .connecting
        currentChannel = channel

        do {
            try AudioSessionController.shared.activateForVoice()
            try await room.connect(url: token.livekitUrl, token: token.token)

            // Publish the mic track but start muted (PTT-released state).
            if channel.canSpeak {
                try await room.localParticipant.setMicrophone(enabled: true)
                if let pub = currentMicPublication() {
                    try await pub.mute()
                }
            }

            routeName = AudioSessionController.shared.currentRouteName
            phase = .connected
            isTransmitting = false
        } catch {
            phase = .failed(error.localizedDescription)
            AudioSessionController.shared.deactivate()
        }
    }

    func disconnect() async {
        await room.disconnect()
        AudioSessionController.shared.deactivate()
        phase = .idle
        isTransmitting = false
        currentChannel = nil
    }

    // MARK: - PTT

    func setTransmitting(_ on: Bool) async {
        guard phase == .connected else { return }
        guard let channel = currentChannel, channel.canSpeak else { return }
        if on && isSelfMuted { return }
        guard let pub = currentMicPublication() else { return }

        do {
            if on {
                try await pub.unmute()
            } else {
                try await pub.mute()
            }
            isTransmitting = on
        } catch {
            // Failure to toggle mute is non-fatal; just log and leave state alone.
            print("RoomController: failed to toggle mute: \(error)")
        }
    }

    func toggleLocked() async {
        isLocked.toggle()
        if isLocked {
            await setTransmitting(true)
        } else {
            await setTransmitting(false)
        }
    }

    // MARK: - Audio routing

    func setSpeaker(on: Bool) {
        do {
            try AudioSessionController.shared.setSpeaker(on: on)
            routeName = AudioSessionController.shared.currentRouteName
        } catch {
            print("RoomController: failed to switch route: \(error)")
        }
    }

    // MARK: - Internals

    private func currentMicPublication() -> LocalTrackPublication? {
        room.localParticipant.audioTracks.compactMap { $0 as? LocalTrackPublication }.first
    }
}
