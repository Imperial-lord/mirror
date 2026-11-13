import SwiftUI
import FirebaseAuth

public struct AuthFlowView: View {
    public var onAuthSuccess: (Bool) -> Void
    @State private var isSignUp = true
    @State private var isShowingVerification = false
    @State private var verificationCode = ""
    @FocusState private var isCodeFocused: Bool
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isResettingPassword = false
    @State private var resetEmail = ""
    @State private var resetMessage: String?
    @State private var resetError: String?
    @State private var isSendingReset = false

    public init(onAuthSuccess: @escaping (Bool) -> Void) {
        self.onAuthSuccess = onAuthSuccess
    }

    public var body: some View {
        Group {
            if isShowingVerification { verificationView }
            else { mainAuthView }
        }
        .tint(.mirrorAccent)
        .sheet(isPresented: $isResettingPassword) { passwordResetSheet }
    }

    private var mainAuthView: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(isSignUp ? "Sign Up" : "Sign In")
                        .font(.system(size: 20, weight: .medium))
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundStyle(Color.mirrorRed)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                    }
                    VStack(spacing: 12) {
                        if isSignUp {
                            TextField("Username", text: $username)
                                .textContentType(.nickname).autocorrectionDisabled().authField()
                        }
                        TextField("E-mail", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().authField()
                        HStack {
                            Group {
                                if isPasswordVisible { TextField(isSignUp ? "Create password" : "Password", text: $password) }
                                else { SecureField(isSignUp ? "Create password" : "Password", text: $password) }
                            }
                            .textContentType(isSignUp ? .newPassword : .password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button { isPasswordVisible.toggle() } label: {
                                PhosphorView(isPasswordVisible ? .eyeSlash : .eye, size: 18, color: .mirrorTextTertiary)
                            }
                            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                        }
                        .authField()
                        if !isSignUp {
                            HStack {
                                #if DEBUG
                                if let demoEmail = ProcessInfo.processInfo.environment["MIRROR_DEMO_EMAIL"],
                                   let demoPassword = ProcessInfo.processInfo.environment["MIRROR_DEMO_PASSWORD"] {
                                    Button("Fill Demo Account") {
                                        email = demoEmail; password = demoPassword; username = "Demo User"
                                    }
                                }
                                #endif
                                Spacer()
                                Button("Forgot Password?") {
                                    resetEmail = email; resetError = nil; resetMessage = nil; isResettingPassword = true
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
                        }
                    }
                    Button(action: authenticate) {
                        Group {
                            if isLoading { ProgressView().tint(Color.mirrorOnInk) }
                            else { Text(isSignUp ? "Sign Up" : "Sign In").font(.system(size: 14, weight: .semibold)) }
                        }
                        .foregroundStyle(Color.mirrorOnInk).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.mirrorInk, in: Capsule())
                    }
                    .padding(.top, 24)
                    Text("By continuing, you accept our Privacy Policy")
                        .font(.system(size: 10)).foregroundStyle(Color.mirrorTextTertiary).padding(.top, 12)
                    Spacer(minLength: 48)
                    HStack(spacing: 12) {
                        Rectangle().fill(Color.mirrorInk.opacity(0.09)).frame(height: 1)
                        Text("Or Continue with").font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary).fixedSize()
                        Rectangle().fill(Color.mirrorInk.opacity(0.09)).frame(height: 1)
                    }
                    HStack(spacing: 12) {
                        Button(action: signInWithGoogle) {
                            PhosphorView(.googleLogo, size: 24)
                                .frame(width: 64, height: 64).background(Color.mirrorSurface1, in: Circle())
                        }
                        .accessibilityLabel("Continue with Google")
                        Button {} label: {
                            PhosphorView(.appleLogo, size: 24)
                                .frame(width: 64, height: 64).background(Color.mirrorSurface1, in: Circle())
                        }
                        .accessibilityLabel("Continue with Apple")
                    }
                    .padding(.top, 36)
                    Spacer(minLength: 48)
                    Button {
                        isSignUp.toggle(); errorMessage = nil; password = ""
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundStyle(Color.mirrorTextTertiary)
                            Text(isSignUp ? "Sign In" : "Sign Up").foregroundStyle(Color.mirrorInk)
                        }
                        .font(.system(size: 12))
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: geometry.size.height)
                .disabled(isLoading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.mirrorBackground.ignoresSafeArea())

    }

    private var verificationView: some View {
        VStack(spacing: 0) {
            ProfileScreenHeader(title: "Verify Account") {
                isCodeFocused = false
                isShowingVerification = false
                errorMessage = nil
            }
            .disabled(isLoading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Enter the code to verify your account.")
                        .font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                    Text("For now, enter any four digits.")
                        .font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary).padding(.top, 4)
                    ZStack {
                        TextField("4-digit code", text: $verificationCode)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($isCodeFocused).opacity(0.02)
                            .onChange(of: verificationCode) { _, value in
                                verificationCode = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                            }
                        HStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { index in
                                Text(index < verificationCode.count ? String(Array(verificationCode)[index]) : "")
                                    .font(.system(size: 22, weight: .medium))
                                    .frame(maxWidth: .infinity).frame(height: 60)
                                    .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCodeFocused && index == verificationCode.count ? Color.mirrorInk : Color.mirrorInk.opacity(0.15), lineWidth: 1))
                            }
                        }
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle()).onTapGesture { isCodeFocused = true }.padding(.top, 16)
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundStyle(Color.mirrorRed).padding(.top, 12)
                    }
                    Button {
                        guard verificationCode.count == 4 else { return }
                        isCodeFocused = false
                        performAuthentication(creatingAccount: true)
                    } label: {
                        Group {
                            if isLoading { ProgressView().tint(Color.mirrorOnInk) }
                            else { Text("Verify Account").font(.system(size: 14, weight: .semibold)) }
                        }
                        .foregroundStyle(Color.mirrorOnInk).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.mirrorInk, in: Capsule())
                    }
                    .disabled(isLoading || verificationCode.count != 4)
                    .opacity(verificationCode.count == 4 ? 1 : 0.4).padding(.top, 24)
                    Button {
                        verificationCode = ""; isCodeFocused = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Didn't Receive Code?").foregroundStyle(Color.mirrorTextTertiary)
                            Text("Resend Code").foregroundStyle(Color.mirrorInk)
                        }
                        .font(.system(size: 11)).frame(maxWidth: .infinity)
                    }
                    .disabled(isLoading).padding(.top, 24)
                }
                .padding(16)
            }
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .onAppear { isCodeFocused = true }
    }

    private var passwordResetSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Enter your email to request a password reset link.")
                        .foregroundStyle(.secondary)
                    TextField("Email address", text: $resetEmail)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().authField()
                    if let resetError { Text(resetError).foregroundStyle(.red).font(.subheadline) }
                    if let resetMessage { Text(resetMessage).foregroundStyle(.secondary).font(.subheadline) }
                    Button {
                        let trimmed = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.contains("@"), trimmed.contains(".") else {
                            resetError = "Enter a valid email address."
                            return
                        }
                        isSendingReset = true
                        resetError = nil
                        Task {
                            defer { isSendingReset = false }
                            do {
                                try await AuthService.shared.sendPasswordReset(email: trimmed)
                                resetMessage = "If an account exists for this email, you’ll receive a password reset link."
                            } catch { resetError = friendlyError(error) }
                        }
                    } label: {
                        Group {
                            if isSendingReset { ProgressView().tint(Color.mirrorOnInk) }
                            else { Text("Send reset link").fontWeight(.semibold) }
                        }
                        .foregroundStyle(Color.mirrorOnInk).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.mirrorInk, in: Capsule())
                    }
                    .disabled(isSendingReset || resetMessage != nil)
                }
                .padding(24)
            }
            .background(Color(mirrorHex: "121215"))
            .navigationTitle("Reset password").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { isResettingPassword = false }.disabled(isSendingReset) } }
        }
        .tint(.mirrorAccent)
        .interactiveDismissDisabled(isSendingReset)

    }

    private func authenticate() {
        guard !isLoading else { return }
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard !password.isEmpty, !isSignUp || password.count >= 6 else {
            errorMessage = isSignUp ? "Use at least 6 characters for your password." : "Enter your password."
            return
        }
        let trimmedName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSignUp || (1...30).contains(trimmedName.count) else {
            errorMessage = "Enter a name between 1 and 30 characters."
            return
        }
        if isSignUp {
            verificationCode = ""
            isShowingVerification = true
        } else {
            performAuthentication(creatingAccount: false)
        }
    }

    private func performAuthentication(creatingAccount: Bool) {
        guard !isLoading else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                if creatingAccount {
                    try await AuthService.shared.signUp(email: trimmedEmail, password: password, username: trimmedName)
                } else {
                    try await AuthService.shared.signIn(email: trimmedEmail, password: password)
                }
                HapticManager.shared.notification(.success)
                onAuthSuccess(creatingAccount)
            } catch {
                HapticManager.shared.notification(.error)
                errorMessage = friendlyError(error)
            }
        }
    }

    private func signInWithGoogle() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let isNewUser = try await AuthService.shared.signInWithGoogle()
                onAuthSuccess(isNewUser)
            } catch {
                let nsError = error as NSError
                if nsError.domain != "com.google.GIDSignIn" || nsError.code != -5 {
                    errorMessage = friendlyError(error)
                }
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) else { return error.localizedDescription }
        switch code {
        case .emailAlreadyInUse: return "This email is already registered. Sign in instead."
        case .invalidEmail: return "Enter a valid email address."
        case .wrongPassword, .invalidCredential, .userNotFound: return "The email or password is incorrect. Try again or reset your password."
        case .weakPassword: return "Choose a stronger password with at least 6 characters."
        case .networkError: return "Check your internet connection and try again."
        case .tooManyRequests: return "Too many attempts. Please try again later."
        case .userDisabled: return "This account has been disabled."
        default: return error.localizedDescription
        }
    }
}

private extension View {
    func authField() -> some View {
        self.font(.system(size: 14)).padding(.horizontal, 16).frame(height: 56)
            .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
    }
}
