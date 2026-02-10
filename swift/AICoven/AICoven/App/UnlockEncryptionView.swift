import SwiftUI

/// Simple unlock screen for the local encryption key.
///
/// The app stores all sensitive local data (threads, messages, memories,
/// settings) encrypted with a key derived from a user-provided passphrase.
/// This view prompts for that passphrase and calls
/// `DataEncryptionService.shared.unlock(withPassphrase:)`.
struct UnlockEncryptionView: View {
    @State private var passphrase: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoDeviceUnlock = false

    /// Called once the encryption key has been successfully unlocked.
    let onUnlocked: () -> Void

    var body: some View {
        ZStack {
            NebulaBackground()

            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    Text("Unlock local data")
                        .font(.aicovenDisplayMedium)
                        .foregroundColor(.aicovenTextPrimary)

                    Text("Enter your passphrase to decrypt chats, memories, and settings stored on this device.")
                        .font(.aicovenBody)
                        .foregroundColor(.aicovenTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if let error = errorMessage {
                        ErrorBannerView(message: error) {
                            errorMessage = nil
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, Spacing.md)
                    }
                }
                .padding(.top, Spacing.xl)

                // Device auth button
                Button(action: { unlockWithDeviceAuth(auto: false) }) {
                    HStack {
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                                .foregroundColor(.white)
                            Text("Unlock with Face ID / Touch ID / Passcode")
                                .font(.aicovenBodyMedium)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.aicovenTeal, Color.aicovenPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(BorderRadius.md)
                    .shadow(
                        color: Color.aicovenTeal.opacity(0.5),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Passphrase")
                            .font(.aicovenH3)
                            .foregroundColor(.aicovenTextPrimary)

                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "lock")
                                .foregroundColor(.aicovenTextTertiary)

                            SecureField("Your encryption passphrase", text: $passphrase)
                                .textContentType(.password)
                                .foregroundColor(.aicovenTextPrimary)
                        }
                        .padding(Spacing.md)
                        .background(Color.aicovenGlass)
                        .cornerRadius(BorderRadius.md)
                    }

                    Button(action: unlock) {
                        HStack {
                            if isWorking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Unlock")
                                    .font(.aicovenBodyMedium)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.md)
                        .background(
                            LinearGradient(
                                colors: [Color.aicovenTeal, Color.aicovenPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(BorderRadius.md)
                        .shadow(
                            color: canSubmit ? Color.aicovenTeal.opacity(0.5) : .clear,
                            radius: 12,
                            x: 0,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isWorking)
                    .opacity(canSubmit && !isWorking ? 1.0 : 0.5)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, Spacing.lg)

                Spacer()
            }
        }
        .task {
            // Try device auth once on first appearance; if it fails, we show
            // the fallback UI without putting the app into a read-only mode.
            if !didAttemptAutoDeviceUnlock {
                didAttemptAutoDeviceUnlock = true
                unlockWithDeviceAuth(auto: true)
            }
        }
    }

    private var canSubmit: Bool {
        !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func unlock() {
        guard canSubmit else { return }
        errorMessage = nil
        isWorking = true
        let entered = passphrase

        Task {
            do {
                try await DataEncryptionService.shared.unlock(withPassphrase: entered)
                await MainActor.run {
                    isWorking = false
                    errorMessage = nil
                    onUnlocked()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    // Surface a friendly error; underlying errorDescription already
                    // includes a useful message for wrong passphrases.
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func unlockWithDeviceAuth(auto: Bool) {
        // Avoid overlapping attempts
        if isWorking { return }
        errorMessage = nil
        isWorking = true

        Task {
            do {
                try await DataEncryptionService.shared.unlockWithDeviceAuthentication()
                await MainActor.run {
                    isWorking = false
                    errorMessage = nil
                    onUnlocked()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    // For auto attempts, keep the message mild; for manual
                    // retries it's fine to show the underlying error.
                    if auto {
                        errorMessage = "Device authentication was canceled or failed. You can try again or unlock with your passphrase."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

#Preview {
    UnlockEncryptionView(onUnlocked: {})
}
