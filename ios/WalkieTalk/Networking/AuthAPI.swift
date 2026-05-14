import Foundation

struct SignupRequest: Encodable {
    let email: String
    let password: String
    let invite_code: String
    let display_name: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RefreshRequest: Encodable {
    let refresh_token: String
}

enum AuthAPI {
    static func signup(_ req: SignupRequest) async throws -> AuthTokens {
        try await APIClient.shared.post("auth/signup", body: req, authenticated: false)
    }

    static func login(_ req: LoginRequest) async throws -> AuthTokens {
        try await APIClient.shared.post("auth/login", body: req, authenticated: false)
    }

    static func refresh(_ refreshToken: String) async throws -> AuthTokens {
        try await APIClient.shared.post(
            "auth/refresh",
            body: RefreshRequest(refresh_token: refreshToken),
            authenticated: false
        )
    }

    static func me() async throws -> MeResponse {
        try await APIClient.shared.get("me")
    }
}
