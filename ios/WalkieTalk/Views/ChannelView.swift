import SwiftUI

struct ChannelView: View {
    @Environment(\.dismiss) private var dismiss
    let channel: Channel
    @State private var room = RoomController()

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            voiceControls
            Spacer()
            statusStrip
        }
        .padding()
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await joinIfNeeded()
        }
        .onDisappear {
            Task { await room.disconnect() }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let desc = channel.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            phaseBadge
        }
    }

    @ViewBuilder
    private var phaseBadge: some View {
        switch room.phase {
        case .idle:
            Label("Idle", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…").foregroundStyle(.secondary)
            }
        case .connected:
            Label("Connected", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(spacing: 6) {
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { Task { await joinIfNeeded(force: true) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var voiceControls: some View {
        VStack(spacing: 28) {
            pttButton
            HStack(spacing: 24) {
                lockToggle
                muteToggle
                speakerToggle
            }
        }
    }

    private var pttButton: some View {
        let active = room.isTransmitting
        let canSpeak = channel.canSpeak && room.phase == .connected && !room.isSelfMuted && !room.isLocked
        return ZStack {
            // animated ring while transmitting
            Circle()
                .stroke(active ? Color.accentColor : Color.clear, lineWidth: 6)
                .frame(width: 220, height: 220)
                .scaleEffect(active ? 1.06 : 1.0)
                .animation(
                    active ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                    value: active
                )

            Circle()
                .fill(active ? Color.accentColor : Color.accentColor.opacity(canSpeak ? 0.85 : 0.25))
                .frame(width: 200, height: 200)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: active ? "waveform" : "mic.fill")
                            .font(.system(size: 56, weight: .semibold))
                        Text(buttonLabel)
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                )
                .shadow(color: active ? Color.accentColor.opacity(0.6) : .clear, radius: 12)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard canSpeak, !room.isTransmitting else { return }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task { await room.setTransmitting(true) }
                }
                .onEnded { _ in
                    guard room.isTransmitting, !room.isLocked else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await room.setTransmitting(false) }
                }
        )
        .disabled(!canSpeak && !room.isLocked)
        .accessibilityLabel("Push to talk")
        .accessibilityHint("Hold to transmit. Release to stop.")
    }

    private var buttonLabel: String {
        if room.isSelfMuted { return "Mic off" }
        if !channel.canSpeak { return "Listen only" }
        if room.isLocked { return "Locked on" }
        if room.isTransmitting { return "Talking" }
        return "Hold to talk"
    }

    private var lockToggle: some View {
        Button {
            Task { await room.toggleLocked() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: room.isLocked ? "lock.fill" : "lock.open")
                    .font(.title2)
                Text("Lock").font(.caption)
            }
            .frame(width: 64, height: 64)
            .background(room.isLocked ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(room.isLocked ? Color.accentColor : Color.primary)
        }
        .disabled(!channel.canSpeak || room.phase != .connected)
    }

    private var muteToggle: some View {
        Button {
            room.isSelfMuted.toggle()
            if room.isSelfMuted {
                Task { await room.setTransmitting(false) }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: room.isSelfMuted ? "mic.slash.fill" : "mic")
                    .font(.title2)
                Text(room.isSelfMuted ? "Muted" : "Mic").font(.caption)
            }
            .frame(width: 64, height: 64)
            .background(room.isSelfMuted ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(room.isSelfMuted ? Color.red : Color.primary)
        }
        .disabled(!channel.canSpeak)
    }

    private var speakerToggle: some View {
        Button {
            let next = !AudioSessionController.shared.isSpeakerOn
            room.setSpeaker(on: next)
        } label: {
            let on = AudioSessionController.shared.isSpeakerOn
            VStack(spacing: 4) {
                Image(systemName: on ? "speaker.wave.2.fill" : "ear")
                    .font(.title2)
                Text(on ? "Speaker" : "Earpiece").font(.caption)
            }
            .frame(width: 64, height: 64)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var statusStrip: some View {
        VStack(spacing: 2) {
            Text("Route: \(room.routeName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func joinIfNeeded(force: Bool = false) async {
        if !force, case .connected = room.phase { return }
        do {
            let token = try await ChannelsAPI.joinToken(channelId: channel.id)
            await room.connect(to: channel, token: token)
        } catch {
            room.markFailed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
