import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case bootstrapping
        case loggedOut
        case loggedIn(MeResponse)
    }

    private(set) var phase: Phase = .bootstrapping
    var lastError: String?

    private var tokens: AuthTokens?

    init() {}

    /// Wire up the APIClient and try to restore a session from Keychain.
    func bootstrap() async {
        await APIClient.shared.configure(
            tokenProvider: { [weak self] in
                guard let self else { return nil }
                return await self.currentTokens()
            },
            tokenRefresher: { [weak self] refresh in
                guard let self else { throw APIError.noTokens }
                return try await self.performRefresh(refresh)
            },
            onUnauthorized: { [weak self] in
                await self?.signOut(silently: true)
            }
        )

        guard let stored = KeychainStore.load() else {
            phase = .loggedOut
            return
        }
        tokens = stored
        await loadMe()
    }

    func signUp(email: String, password: String, inviteCode: String, displayName: String) async {
        do {
            let t = try await AuthAPI.signup(.init(
                email: email,
                password: password,
                invite_code: inviteCode,
                display_name: displayName
            ))
            try await persist(tokens: t)
            await loadMe()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let t = try await AuthAPI.login(.init(email: email, password: password))
            try await persist(tokens: t)
            await loadMe()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut(silently: Bool = false) async {
        tokens = nil
        KeychainStore.clear()
        phase = .loggedOut
        if !silently { lastError = nil }
    }

    // MARK: - APIClient hooks (called from the APIClient actor)

    nonisolated func currentTokens() async -> AuthTokens? {
        await MainActor.run { tokens }
    }

    nonisolated func performRefresh(_ refresh: String) async throws -> AuthTokens {
        let fresh = try await AuthAPI.refresh(refresh)
        try await MainActor.run {
            try KeychainStore.save(fresh)
            self.tokens = fresh
        }
        return fresh
    }

    // MARK: - Internals

    private func persist(tokens new: AuthTokens) async throws {
        try KeychainStore.save(new)
        tokens = new
    }

    private func loadMe() async {
        do {
            let me = try await AuthAPI.me()
            phase = .loggedIn(me)
            lastError = nil
        } catch {
            // If /me fails right after sign-in, drop the session and surface the error.
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await signOut(silently: true)
        }
    }
}
