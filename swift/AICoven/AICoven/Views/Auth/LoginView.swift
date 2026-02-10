import SwiftUI

/// Enhanced login screen with improved UX and visual design
struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    
    @State private var mode: AuthMode = .signin
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showForgotPassword = false
    @State private var emailFieldFocused = false
    @State private var passwordFieldFocused = false
    @State private var confirmPasswordFieldFocused = false
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    enum AuthMode {
        case signin, signup
    }
    
    var body: some View {
        ZStack {
            Color.aicovenDark
                .ignoresSafeArea()

            if mode == .signup {
                signupContent
            } else {
                signinContent
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    
    /// Fallback app icon with enhanced styling
    private var appIconFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.aicovenTeal.opacity(0.2), Color.aicovenPurple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
            
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.aicovenTeal, Color.aicovenPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: Color.aicovenTeal.opacity(0.5), radius: 20, x: 0, y: 0)
    }
    
    /// Load app icon from resources
    #if os(iOS)
    private func loadAppIcon() -> UIImage? {
        // Try loading from asset catalog first
        if let image = UIImage(named: "icon") {
            return image
        }
        // Try loading from Resources folder
        if let path = Bundle.main.path(forResource: "icon", ofType: "png", inDirectory: "Resources") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
    #elseif os(macOS)
    private func loadAppIcon() -> NSImage? {
        // Try loading from asset catalog first
        if let image = NSImage(named: "icon") {
            return image
        }
        // Try loading from Resources folder
        if let path = Bundle.main.path(forResource: "icon", ofType: "png", inDirectory: "Resources") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }
    #else
    private func loadAppIcon() -> Void { return nil }
    #endif
    
    /// Check if form is valid
    private var isFormValid: Bool {
        if mode == .signin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !firstName.isEmpty && !lastName.isEmpty && !email.isEmpty &&
                passwordRequirementsMet && password == confirmPassword
        }
    }

    private var passwordRequirementsMet: Bool {
        password.count >= 8 &&
        password.containsUppercase &&
        password.containsLowercase &&
        password.containsNumber &&
        password.containsSpecialCharacter
    }
    
    /// Handle form submission
    private func handleSubmit() {
        isLoading = true
        Task {
            do {
                if mode == .signin {
                    // Track login attempt (no PII)
                    AnalyticsService.shared.track(
                        event: "login_attempt",
                        properties: [
                            "method": "email"
                        ]
                    )
                    
                    try await authService.signIn(email: email, password: password)
                    
                    // Track successful login
                    AnalyticsService.shared.trackLogin(method: "email")
                } else {
                    let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let components = [trimmedFirst, trimmedLast].filter { !$0.isEmpty }
                    let fullName = components.joined(separator: " ")
                    let nameParam: String? = fullName.isEmpty ? nil : fullName
                    
                    // Track signup attempt (no PII)
                    AnalyticsService.shared.track(
                        event: "signup_attempt",
                        properties: [
                            "method": "email",
                            "has_name": nameParam != nil
                        ]
                    )
                    
                    try await authService.signUp(email: email, password: password, name: nameParam)
                    
                    // Track successful signup
                    AnalyticsService.shared.trackSignUp(method: "email")
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                
                // Track authentication failure (no PII)
                AnalyticsService.shared.trackAuthError(
                    error: error.localizedDescription,
                    method: "email"
                )
            }
            isLoading = false
        }
    }
}

// MARK: - Auth Mode Button Component

/// Custom tab-like button for auth mode selection
struct AuthModeButton: View {
    let title: String
    let isSelected: Bool
    let position: Position
    let action: () -> Void
    
    enum Position {
        case left, right
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.aicovenBodyMedium)
                .foregroundColor(isSelected ? .white : .aicovenTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    ZStack {
                        if isSelected {
                            LinearGradient(
                                colors: [Color.aicovenTeal.opacity(0.3), Color.aicovenPurple.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            Color.aicovenGlass
                        }
                    }
                )
                .overlay(
                    Rectangle()
                        .fill(isSelected ? Color.aicovenTeal : Color.clear)
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
        }
        .buttonStyle(.plain)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: position == .left ? BorderRadius.md : 0,
                bottomLeadingRadius: position == .left ? BorderRadius.md : 0,
                bottomTrailingRadius: position == .right ? BorderRadius.md : 0,
                topTrailingRadius: position == .right ? BorderRadius.md : 0
            )
        )
    }
}

// MARK: - Signup Tutorial Layout

private extension LoginView {
    var signupContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                signupHero

                VStack(spacing: Spacing.lg) {
                    signupStepper

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Create your account")
                            .font(.aicovenH1)
                            .foregroundColor(.aicovenTextPrimary)
                        Text("Join the circle of intelligences")
                            .font(.aicovenBodySmall)
                            .foregroundColor(.aicovenTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            SignupTextField(
                                label: "First Name",
                                placeholder: "John",
                                text: $firstName
                            )
                            SignupTextField(
                                label: "Last Name",
                                placeholder: "Doe",
                                text: $lastName
                            )
                        }

                        SignupTextField(
                            label: "Email address",
                            placeholder: "you@example.com",
                            text: $email,
                            icon: "envelope"
                        )
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif

                        SignupTextField(
                            label: "Password",
                            placeholder: "At least 8 characters",
                            text: $password,
                            icon: "lock",
                            isSecure: true,
                            isSecureVisible: $isPasswordVisible
                        )
                        .textContentType(.newPassword)

                        PasswordRequirementsView(password: password)

                        SignupTextField(
                            label: "Confirm Password",
                            placeholder: "Confirm your password",
                            text: $confirmPassword,
                            icon: "lock",
                            isSecure: true,
                            isSecureVisible: $isConfirmPasswordVisible
                        )
                        .textContentType(.newPassword)
                    }

                    Button(action: handleSubmit) {
                        HStack(spacing: Spacing.xs) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Continue")
                                    .font(.aicovenBodyMedium)
                                    .foregroundColor(.white)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#009689"), Color(hex: "#00BBA7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid && !isLoading ? 1.0 : 0.5)

                    HStack(spacing: Spacing.xs) {
                        Text("Already have an account?")
                            .font(.aicovenBodySmall)
                            .foregroundColor(.aicovenTextSecondary)
                        Button("Sign in") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mode = .signin
                            }
                        }
                        .font(.aicovenBodySmall)
                        .foregroundColor(Color(hex: "#00D5BE"))
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Spacing.xl)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .background(Color(hex: "#101828"))
            }
        }
    }

    var signinContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        if let iconImage = loadAppIcon() {
                            #if os(iOS)
                            Image(uiImage: iconImage)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.aicovenTeal.opacity(0.5), radius: 20, x: 0, y: 0)
                            #elseif os(macOS)
                            Image(nsImage: iconImage)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.aicovenTeal.opacity(0.5), radius: 20, x: 0, y: 0)
                            #endif
                        } else {
                            appIconFallback
                        }

                        Text("Welcome Back")
                            .font(.aicovenDisplayMedium)
                            .foregroundColor(.aicovenTextPrimary)

                        Text("Sign in to your account")
                            .font(.aicovenBody)
                            .foregroundColor(.aicovenTextSecondary)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 32)

                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.aicovenH3)
                                .foregroundColor(.aicovenTextPrimary)

                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16))
                                    .foregroundColor(emailFieldFocused ? .aicovenTeal : .aicovenTextTertiary)

                                TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(.aicovenTextTertiary))
                                    .textContentType(.emailAddress)
                                    #if os(iOS)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    #endif
                                    .foregroundColor(.aicovenTextPrimary)
                                    .disabled(isLoading)
                            }
                            .padding(16)
                            .background(Color.aicovenGlass)
                            .cornerRadius(BorderRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: BorderRadius.md)
                                    .strokeBorder(
                                        emailFieldFocused ? Color.aicovenTeal : Color.aicovenBorder,
                                        lineWidth: emailFieldFocused ? 2 : 1
                                    )
                            )
                            .shadow(
                                color: emailFieldFocused ? Color.aicovenTeal.opacity(0.3) : .clear,
                                radius: 8,
                                x: 0,
                                y: 0
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.aicovenH3)
                                .foregroundColor(.aicovenTextPrimary)

                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16))
                                    .foregroundColor(passwordFieldFocused ? .aicovenTeal : .aicovenTextTertiary)

                                SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(.aicovenTextTertiary))
                                    .textContentType(.password)
                                    .foregroundColor(.aicovenTextPrimary)
                                    .disabled(isLoading)
                            }
                            .padding(16)
                            .background(Color.aicovenGlass)
                            .cornerRadius(BorderRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: BorderRadius.md)
                                    .strokeBorder(
                                        passwordFieldFocused ? Color.aicovenTeal : Color.aicovenBorder,
                                        lineWidth: passwordFieldFocused ? 2 : 1
                                    )
                            )
                            .shadow(
                                color: passwordFieldFocused ? Color.aicovenTeal.opacity(0.3) : .clear,
                                radius: 8,
                                x: 0,
                                y: 0
                            )
                        }

                        HStack {
                            Spacer()
                            Button {
                                showForgotPassword = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.aicovenBodySmall)
                                    .foregroundColor(.aicovenTeal)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                        }
                        .padding(.top, -8)

                        Button(action: handleSubmit) {
                            HStack(spacing: Spacing.xs) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Sign In")
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
                                color: isFormValid && !isLoading ? Color.aicovenTeal.opacity(0.5) : .clear,
                                radius: 12,
                                x: 0,
                                y: 4
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || !isFormValid)
                        .opacity(isFormValid && !isLoading ? 1.0 : 0.5)

                        Button("Create account") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mode = .signup
                            }
                        }
                        .font(.aicovenBodySmall)
                        .foregroundColor(.aicovenTeal)
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.sm)
                    }
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    var signupHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#101828"),
                    Color(hex: "#1E2939"),
                    Color(hex: "#101828")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color(hex: "#009689").opacity(0.35),
                    Color(hex: "#9810FA").opacity(0.35),
                    Color(hex: "#E60076").opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: Spacing.sm) {
                if let iconImage = loadAppIcon() {
                    #if os(iOS)
                    Image(uiImage: iconImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    #elseif os(macOS)
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    #endif
                } else {
                    appIconFallback
                }

                Text("AICoven")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Text("Technology so advanced, it feels like magic.")
                    .font(.aicovenBody)
                    .italic()
                    .foregroundColor(Color(hex: "#46ECD5"))

                Text("Orchestrate every model. Preserve every memory.")
                    .font(.aicovenBodySmall)
                    .foregroundColor(Color(hex: "#99A1AF"))
            }
            .padding(.top, Spacing.xl)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
    }

    var signupStepper: some View {
        HStack(spacing: Spacing.xs) {
            SignupStepIndicator(number: "1", title: "Account", isActive: true)
            SignupStepperConnector()
            SignupStepIndicator(number: "2", title: "Privacy", isActive: false)
            SignupStepperConnector()
            SignupStepIndicator(number: "3", title: "Keys", isActive: false)
            SignupStepperConnector()
            SignupStepIndicator(number: "4", title: "Complete", isActive: false)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SignupTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure = false
    var isSecureVisible: Binding<Bool>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.aicovenBodySmall)
                .foregroundColor(.aicovenTextSecondary)

            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.aicovenTextTertiary)
                }

                if isSecure, let isSecureVisible {
                    if isSecureVisible.wrappedValue {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.aicovenTextTertiary))
                            .foregroundColor(.aicovenTextPrimary)
                    } else {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.aicovenTextTertiary))
                            .foregroundColor(.aicovenTextPrimary)
                    }
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.aicovenTextTertiary))
                        .foregroundColor(.aicovenTextPrimary)
                }

                if isSecure, let isSecureVisible {
                    Button {
                        isSecureVisible.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isSecureVisible.wrappedValue ? "eye" : "eye.slash")
                            .font(.system(size: 14))
                            .foregroundColor(.aicovenTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(hex: "#1E2939"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(hex: "#364153"), lineWidth: 1)
            )
        }
    }
}

private struct SignupStepIndicator: View {
    let number: String
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(isActive ? Color(hex: "#009689") : Color(hex: "#1E2939"))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(isActive ? Color(hex: "#009689") : Color(hex: "#364153"), lineWidth: 1)
                    )

                Text(number)
                    .font(.aicovenBodyMedium)
                    .foregroundColor(isActive ? .white : Color(hex: "#6A7282"))
            }

            Text(title)
                .font(.aicovenCaption)
                .foregroundColor(isActive ? .aicovenTextPrimary : Color(hex: "#4A5565"))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PasswordRequirementsView: View {
    let password: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            RequirementRow(
                title: "At least 8 characters",
                isMet: password.count >= 8
            )
            RequirementRow(
                title: "1 uppercase letter",
                isMet: password.containsUppercase
            )
            RequirementRow(
                title: "1 lowercase letter",
                isMet: password.containsLowercase
            )
            RequirementRow(
                title: "1 number",
                isMet: password.containsNumber
            )
            RequirementRow(
                title: "1 special character",
                isMet: password.containsSpecialCharacter
            )
        }
        .padding(.horizontal, Spacing.xxs)
    }
}

private struct RequirementRow: View {
    let title: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(isMet ? Color(hex: "#00D5BE") : .aicovenTextTertiary)
            Text(title)
                .font(.aicovenCaption)
                .foregroundColor(isMet ? .aicovenTextPrimary : .aicovenTextTertiary)
        }
    }
}

private extension String {
    var containsUppercase: Bool {
        rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    var containsLowercase: Bool {
        rangeOfCharacter(from: .lowercaseLetters) != nil
    }

    var containsNumber: Bool {
        rangeOfCharacter(from: .decimalDigits) != nil
    }

    var containsSpecialCharacter: Bool {
        rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
    }
}

private struct SignupStepperConnector: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "#1E2939"))
            .frame(width: 24, height: 2)
    }
}
#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
