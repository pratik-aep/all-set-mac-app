import AllSetCore
import SwiftUI

/// Covers the window until the person has signed in to the wallpaper library
/// (or, with a temporary password, has chosen their own). Only shown when a
/// library server is set; with none, the app opens as it always did.
struct LibrarySignInGate: View {
    @Bindable var account: LibraryAccount

    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var problem: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            DS.Surface.canvas.ignoresSafeArea()
            GlassPanel(cornerRadius: 24, padding: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Text("All Set")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Ink.secondary)
                    switch account.state {
                    case .mustChangePassword(let who): changePassword(who)
                    default: signIn
                    }
                    if let problem {
                        Text(problem)
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 320)
            }
        }
    }

    private var signIn: some View {
        Group {
            Text("Sign in to your wallpapers")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Ink.primary)
            Text("Use the email and password from your invitation.")
                .font(.system(size: 13))
                .foregroundStyle(DS.Ink.secondary)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .disableAutocorrection(true)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitSignIn)
            Button(action: submitSignIn) {
                Text(isWorking ? "Signing in\u{2026}" : "Sign In").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillProminent)
            .disabled(isWorking || email.isEmpty || password.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func changePassword(_ who: String) -> some View {
        Group {
            Text("Choose your password")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Ink.primary)
            Text("You signed in to \(who) with a temporary password. Choose your own to continue.")
                .font(.system(size: 13))
                .foregroundStyle(DS.Ink.secondary)
            SecureField("New password (at least 10 characters)", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("Type it again", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitNewPassword)
            Button(action: submitNewPassword) {
                Text(isWorking ? "Saving\u{2026}" : "Save and Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillProminent)
            .disabled(isWorking || newPassword.isEmpty || confirmation.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func submitSignIn() {
        guard !isWorking, !email.isEmpty, !password.isEmpty else { return }
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.signIn(email: email, password: password)
                password = ""
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func submitNewPassword() {
        guard !isWorking else { return }
        guard newPassword == confirmation else {
            problem = "The two passwords don\u{2019}t match."
            return
        }
        guard newPassword.count >= 10 else {
            problem = "Use at least 10 characters."
            return
        }
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.setPassword(newPassword)
                newPassword = ""
                confirmation = ""
                password = ""
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

/// The signed-in person and a way to sign out, on the General page.
struct LibraryAccountSettings: View {
    let account: LibraryAccount

    var body: some View {
        Section {
            LabeledContent {
                if account.isSignedIn {
                    Button("Sign Out") { account.signOut() }
                }
            } label: {
                Text("Wallpaper library")
                Text(statusLine)
            }
        }
    }

    private var statusLine: String {
        switch account.state {
        case .signedIn(let email): "Signed in as \(email)."
        case .mustChangePassword(let email): "\(email) needs a new password."
        case .signedOut: "Not signed in."
        }
    }
}
