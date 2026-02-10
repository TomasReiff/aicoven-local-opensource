import SwiftUI

/// Forgot password screen
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction
    @EnvironmentObject var authService: AuthService
    
    @State private var email = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    /// Explicit initializer for SwiftUI previews
    init() {}
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal, 32)
                
                Button(action: handleResetPassword) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading || email.isEmpty)
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .padding()
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Track password reset cancellation
                        AnalyticsService.shared.track(
                            event: "password_reset_cancelled",
                            properties: [
                                "email_entered": !email.isEmpty
                            ]
                        )
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("If this email is associated with an account, a reset password link was sent.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Track forgot password view appearance
            AnalyticsService.shared.track(
                event: "password_reset_view_opened",
                properties: [:]
            )
        }
    }
    
    /// Handle password reset action
    private func handleResetPassword() {
        isLoading = true
        
        // Track password reset attempt (no PII)
        AnalyticsService.shared.track(
            event: "password_reset_attempt",
            properties: [:]
        )
        
        Task {
            do {
                try await authService.sendPasswordReset(email: email)
                
                // Track successful password reset request (no PII)
                AnalyticsService.shared.track(
                    event: "password_reset_success",
                    properties: [:]
                )
                
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                
                // Track password reset failure (no PII)
                AnalyticsService.shared.track(
                    event: "password_reset_failed",
                    properties: [
                        "error": error.localizedDescription
                    ]
                )
                
                showError = true
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
            .environmentObject(AuthService.shared)
    }
}
