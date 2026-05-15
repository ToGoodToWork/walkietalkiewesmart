import Foundation

enum ChannelsAPI {
    static func list() async throws -> [Channel] {
        try await APIClient.shared.get("channels")
    }

    static func joinToken(channelId: String) async throws -> JoinToken {
        struct Empty: Encodable {}
        return try await APIClient.shared.post("channels/\(channelId)/join-token", body: Empty())
    }
}
