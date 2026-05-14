import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    enum Mode: String, CaseIterable { case login = "Sign in", signup = "Sign up" }
    @State private var mode: Mode = .login

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var inviteCode = ""
    @State private var submitting = false

    @FocusState private var focused: Field?
    enum Field { case email, password, displayName, invite }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    form
                    submitButton
                    if let err = auth.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("WalkieTalk")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text(mode == .login ? "Welcome back." : "Create your account")
                .font(.title3.weight(.semibold))
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var form: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(mode == .login ? .password : .newPassword)
                .focused($focused, equals: .password)
                .submitLabel(mode == .login ? .done : .next)
                .onSubmit {
                    if mode == .login { Task { await submit() } }
                    else { focused = .displayName }
                }
                .textFieldStyle(.roundedBorder)

            if mode == .signup {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .focused($focused, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focused = .invite }
                    .textFieldStyle(.roundedBorder)

                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .invite)
                    .submitLabel(.done)
                    .onSubmit { Task { await submit() } }
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Working..." : mode.rawValue).bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(submitting || !canSubmit)
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 8 else { return false }
        if mode == .signup {
            return !displayName.isEmpty && !inviteCode.isEmpty
        }
        return true
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        switch mode {
        case .login:
            await auth.signIn(email: email, password: password)
        case .signup:
            await auth.signUp(
                email: email,
                password: password,
                inviteCode: inviteCode,
                displayName: displayName
            )
        }
    }
}
