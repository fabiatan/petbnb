import Foundation
import Supabase
import Auth

struct AuthSignUpInput {
    let email: String
    let password: String
    let displayName: String
}

enum AuthServiceError: LocalizedError {
    case signUpFailed(String)
    case signInFailed(String)
    case profileCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .signUpFailed(let m): "Sign up failed: \(m)"
        case .signInFailed(let m): "Sign in failed: \(m)"
        case .profileCreationFailed(let m): "Profile creation failed: \(m)"
        }
    }
}

@MainActor
final class AuthService {
    enum AuthEvent {
        case signedIn(userId: UUID, displayName: String)
        case signedOut
    }

    private let client: SupabaseClient
    private let profileFetcher: UserProfileFetcher

    init(client: SupabaseClient, profileFetcher: UserProfileFetcher? = nil) {
        self.client = client
        self.profileFetcher = profileFetcher ?? LiveUserProfileFetcher(client: client)
    }

    func signUp(_ input: AuthSignUpInput) async throws {
        do {
            let resp = try await client.auth.signUp(
                email: input.email,
                password: input.password,
                data: ["display_name": .string(input.displayName)]
            )
            let userId = resp.user.id

            // Insert profile row (RLS policy allows self-insert).
            do {
                try await client.from("user_profiles")
                    .insert(["id": userId.uuidString, "display_name": input.displayName])
                    .execute()
            } catch {
                throw AuthServiceError.profileCreationFailed(error.localizedDescription)
            }
        } catch let e as AuthServiceError {
            throw e
        } catch {
            throw AuthServiceError.signUpFailed(error.localizedDescription)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw AuthServiceError.signInFailed(error.localizedDescription)
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Emits an event for every session change (and a synthetic first event for
    /// the current state on subscription).
    func authEvents() -> AsyncStream<AuthEvent> {
        AsyncStream { continuation in
            let task = Task { [profileFetcher, client] in
                for await (_, session) in client.auth.authStateChanges {
                    if let session {
                        let name = (try? await profileFetcher.displayName(for: session.user.id)) ?? session.user.email ?? "Unknown"
                        continuation.yield(.signedIn(userId: session.user.id, displayName: name))
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

protocol UserProfileFetcher: Sendable {
    func displayName(for userId: UUID) async throws -> String?
}

struct LiveUserProfileFetcher: UserProfileFetcher {
    let client: SupabaseClient

    func displayName(for userId: UUID) async throws -> String? {
        struct Row: Decodable { let display_name: String }
        let rows: [Row] = try await client.from("user_profiles")
            .select("display_name")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.display_name
    }
}
