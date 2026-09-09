import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(StoreManager.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var showDeleteConfirm = false
    @State private var restoreMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Profile")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                if auth.isSignedIn { accountCard } else { signInCard }

                if let error = auth.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                settingsRows

                if auth.isSignedIn {
                    Button("Sign Out") { auth.signOut() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 6)

                    Button("Delete Account") { showDeleteConfirm = true }
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                }

                Text(AppConfig.appVersion)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    .padding(.top, 8)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) { auth.deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out and removes your account details from this device.")
        }
    }

    // MARK: - Signed in

    private var accountCard: some View {
        HStack(spacing: 12) {
            Text(auth.user?.initial ?? "?")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(red: 0.10, green: 0.45, blue: 0.35), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.user?.displayName ?? "Signed in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(auth.user?.email ?? "Apple ID")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if store.isPro {
                Text("PRO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Signed out

    private var signInCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Sign in to TuneTube")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Keep your playlists and purchases with you.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 4)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in
                // Handled by AuthService's own controller so the credential and
                // its Keychain persistence live in one place.
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .overlay(
                Button { Task { await auth.signInWithApple() } } label: {
                    Color.clear
                }
                .accessibilityLabel("Sign in with Apple")
            )

            Button { Task { await auth.signInWithGoogle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 18))
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(auth.isGoogleConfigured ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .disabled(auth.isBusy)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Rows

    private var settingsRows: some View {
        VStack(spacing: 0) {
            row("arrow.clockwise", "Restore Purchases",
                restoreMessage ?? "Restore your previous purchases") {
                Task {
                    await store.restore()
                    restoreMessage = store.isPro ? "Pro restored." : "No purchases found."
                }
            }
            divider
            row("star", "Rate App", "Help us improve with your feedback") {}
            divider
            row("checkmark.shield", "Privacy Policy", nil) {}
            divider
            row("doc.text", "Terms of Service", nil) {}
            divider
            row("questionmark.circle", "Help & Support", "Get assistance via email") {}
            divider
            row("square.grid.2x2", "More Apps", "Check out our other apps") {}
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 50)
    }

    private func row(
        _ icon: String, _ title: String, _ subtitle: String?, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
