import Foundation

struct AuthTokens: Codable, Equatable {
    let access: String
    let refresh: String
}

enum UserStatus: String, Codable {
    case online, busy, dnd, offline
}

struct User: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let avatarUrl: String?
    let status: UserStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, status
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}

struct Org: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct Permissions: Codable, Equatable {
    let manageOrg: Bool
    let manageUsers: Bool
    let manageRoles: Bool
    let manageChannels: Bool
    let whisperAnyone: Bool
    let bypassChannelPerms: Bool

    enum CodingKeys: String, CodingKey {
        case manageOrg = "manage_org"
        case manageUsers = "manage_users"
        case manageRoles = "manage_roles"
        case manageChannels = "manage_channels"
        case whisperAnyone = "whisper_anyone"
        case bypassChannelPerms = "bypass_channel_perms"
    }
}

struct Role: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let color: String
    let position: Int
    let permissions: Permissions
}

struct MeResponse: Codable, Equatable {
    let user: User
    let org: Org
    let roles: [Role]
    let permissions: Permissions
}
