import AuthenticationServices
import Foundation
import SwiftUI

struct AuthUser: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable { case apple, google }

    let id: String                  // stable per-provider user identifier
    var displayName: String?
    var email: String?
    let provider: Provider

    var firstName: String? {
        displayName?.split(separator: " ").first.map(String.init)
    }

    /// Initial for the avatar circle.
    var initial: String {
        let source = displayName ?? email ?? "?"
        return source.first.map { String($0).uppercased() } ?? "?"
    }
}

/// Account identity.
///
/// Sign in with Apple is implemented natively — no third-party SDK. Google
/// sign-in needs an OAuth client id that only the project owner can issue; the
/// button reports precisely what is missing rather than failing silently.
///
/// Note this establishes *identity only*. Playlists remain device-local until
/// there is a backend to sync them to.
@MainActor
@Observable
final class AuthService: NSObject {
    static let shared = AuthService()

    private(set) var user: AuthUser?
    private(set) var lastError: String?
    private(set) var isBusy = false

    private static let account = "signed-in-user"
    private var appleContinuation: CheckedContinuation<AuthUser, Error>?

    var isSignedIn: Bool { user != nil }

    /// Greeting name, falling back to something friendly when signed out.
    var greetingName: String { user?.firstName ?? "there" }

    private override init() {
        super.init()
        restore()
    }

    // MARK: - Persistence

    private func restore() {
        guard
            let data = KeychainStore.load(account: Self.account),
            let stored = try? JSONDecoder().decode(AuthUser.self, from: data)
        else { return }
        user = stored
    }

    private func persist(_ user: AuthUser) {
        self.user = user
        if let data = try? JSONEncoder().encode(user) {
            KeychainStore.save(data, account: Self.account)
        }
    }

    func signOut() {
        user = nil
        lastError = nil
        KeychainStore.delete(account: Self.account)
    }

    /// Clears the local identity. A real deletion also has to remove
    /// server-side data — required by App Review once accounts exist.
    func deleteAccount() {
        signOut()
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let signedIn: AuthUser = try await withCheckedThrowingContinuation { continuation in
                appleContinuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
            persist(signedIn)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // Not an error worth surfacing.
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Google

    /// Set `GIDClientID` in Info.plist to enable. Absent by design: an OAuth
    /// client id has to be issued from the project's own Google Cloud console.
    var googleClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        return (value?.isEmpty == false && value != "$(GID_CLIENT_ID)") ? value : nil
    }

    var isGoogleConfigured: Bool { googleClientID != nil }

    func signInWithGoogle() async {
        guard isGoogleConfigured else {
            lastError = "Google sign-in isn't configured yet. Add a GIDClientID "
                      + "to Info.plist and the GoogleSignIn package."
            return
        }
        // Intentionally unimplemented: wiring this without a client id to test
        // against would be code that has never once been run.
        lastError = "Google sign-in is configured but not yet wired up."
    }
}

// MARK: - Apple delegate plumbing

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else {
            Task { @MainActor in
                self.appleContinuation?.resume(throwing: AuthError.unexpectedCredential)
                self.appleContinuation = nil
            }
            return
        }

        let id = credential.user
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let email = credential.email

        Task { @MainActor in
            // Name and email arrive only on the FIRST authorization. On repeat
            // sign-ins they are nil, so keep whatever we already stored.
            let existing = self.user
            let resolved = AuthUser(
                id: id,
                displayName: name.isEmpty ? existing?.displayName : name,
                email: email ?? existing?.email,
                provider: .apple
            )
            self.appleContinuation?.resume(returning: resolved)
            self.appleContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleContinuation?.resume(throwing: error)
            self.appleContinuation = nil
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

enum AuthError: LocalizedError {
    case unexpectedCredential
    var errorDescription: String? { "Unexpected sign-in response." }
}
