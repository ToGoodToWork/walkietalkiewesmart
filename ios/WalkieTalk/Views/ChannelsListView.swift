import SwiftUI

struct ChannelsListView: View {
    @Environment(AuthStore.self) private var auth
    @State private var channels: [Channel] = []
    @State private var loadError: String?
    @State private var loading = false
    @State private var showSettings = false

    let me: MeResponse

    var body: some View {
        NavigationStack {
            Group {
                if loading && channels.isEmpty {
                    ProgressView().controlSize(.large)
                } else if let err = loadError, channels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Channels") {
                            ForEach(channels) { channel in
                                NavigationLink(value: channel) {
                                    row(for: channel)
                                }
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("WalkieTalk")
            .navigationDestination(for: Channel.self) { channel in
                ChannelView(channel: channel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(me: me)
            }
            .task { await load() }
        }
    }

    private func row(for channel: Channel) -> some View {
        HStack {
            Image(systemName: channel.type == .broadcast ? "megaphone.fill"
                  : channel.type == .private ? "lock.fill"
                  : "number")
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body.weight(.medium))
                if let d = channel.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !channel.canSpeak && channel.canJoin {
                Image(systemName: "ear")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Listen-only")
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            channels = try await ChannelsAPI.list()
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SettingsSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let me: MeResponse

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: me.user.displayName)
                    LabeledContent("Email", value: me.user.email)
                }
                Section("Organization") {
                    LabeledContent("Name", value: me.org.name)
                }
                Section("Roles") {
                    ForEach(me.roles) { role in
                        Text(role.name)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    } label: {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
