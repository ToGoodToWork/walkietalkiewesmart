import SwiftUI

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    let me: MeResponse

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: me.user.displayName)
                    LabeledContent("Email", value: me.user.email)
                    LabeledContent("Status", value: me.user.status.rawValue)
                }

                Section("Organization") {
                    LabeledContent("Name", value: me.org.name)
                    LabeledContent("ID", value: String(me.org.id.prefix(8)) + "…")
                        .monospaced()
                }

                Section("Roles") {
                    if me.roles.isEmpty {
                        Text("No roles assigned").foregroundStyle(.secondary)
                    } else {
                        ForEach(me.roles) { role in
                            HStack {
                                Circle()
                                    .fill(Color(hex: role.color))
                                    .frame(width: 10, height: 10)
                                Text(role.name)
                                Spacer()
                                Text("pos \(role.position)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Permissions") {
                    permRow("Manage organization", me.permissions.manageOrg)
                    permRow("Manage users", me.permissions.manageUsers)
                    permRow("Manage roles", me.permissions.manageRoles)
                    permRow("Manage channels", me.permissions.manageChannels)
                    permRow("Whisper anyone", me.permissions.whisperAnyone)
                    permRow("Bypass channel perms", me.permissions.bypassChannelPerms)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Text("Sign out")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("WalkieTalk")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func permRow(_ label: String, _ value: Bool) -> some View {
        HStack {
            Image(systemName: value ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(value ? Color.green : Color.secondary)
            Text(label)
        }
    }
}

private extension Color {
    /// Parse `#RRGGBB` from the role color string.
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
