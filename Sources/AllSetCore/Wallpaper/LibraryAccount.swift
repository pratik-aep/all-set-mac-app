import Foundation
import Observation
import OSLog

/// Who is signed in to the wallpaper library server, and the session that lets
/// the app download from it. The server (scripts/cloud/accounts.py) only gives
/// accounts to people the owner invites; the session token lives in the
/// Keychain, never in a file.
///
/// The sign-in endpoints sit under `<server>/api/` (Caddy passes them to the
/// catalog service). A temporary password has to be replaced before anything
/// else is allowed, and a session the server stops accepting signs the app out.
@MainActor @Observable
public final class LibraryAccount {
    public enum State: Equatable {
        case signedOut
        case mustChangePassword(email: String)
        case signedIn(email: String)
    }

    public enum Failure: LocalizedError, Equatable {
        case wrongEmailOrPassword
        case tooManyAttempts
        case unreachable
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .wrongEmailOrPassword: "That email and password don't match. Check the invite you were sent."
            case .tooManyAttempts: "Too many attempts. Wait a few minutes, then try again."
            case .unreachable: "Couldn't reach the wallpaper library. Check that Tailscale is connected."
            case .refused(let message): message
            }
        }
    }

    public private(set) var state: State = .signedOut
    /// The library's address (the file server); the account API is under `api/`.
    public let serverURL: URL

    @ObservationIgnored private var token: String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let keychainService: String
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "library-account")

    public static let defaultKeychainService = "com.pratik.allset.library"
    private static let tokenAccount = "session"
    private static let emailAccount = "email"

    public init(serverURL: URL, keychainService: String = LibraryAccount.defaultKeychainService,
                session: URLSession? = nil) {
        self.serverURL = serverURL
        self.keychainService = keychainService
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
        if let saved = KeychainItem.read(service: keychainService, account: Self.tokenAccount),
           let email = KeychainItem.read(service: keychainService, account: Self.emailAccount) {
            token = saved
            state = .signedIn(email: email)
        }
    }

    /// The bearer token to send with library requests, when signed in.
    public var bearerToken: String? {
        if case .signedIn = state { return token }
        return nil
    }

    public var isSignedIn: Bool { if case .signedIn = state { true } else { false } }

    /// Checks a saved session with the server. Only a refusal signs out: when the
    /// server can't be reached the app keeps the saved session, so it still works
    /// on the road.
    public func verify() async {
        guard token != nil else { return }
        do {
            let (status, body) = try await send("me", authorized: true)
            switch status {
            case 200: state = .signedIn(email: body["email"] as? String ?? emailSaved())
            case 403: state = .mustChangePassword(email: emailSaved())
            case 401: forget()
            default: break
            }
        } catch {
            log.info("Could not verify the library session: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func signIn(email: String, password: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let (status, body) = try await send("login", body: ["email": address, "password": password])
        switch status {
        case 200:
            guard let newToken = body["token"] as? String else { throw Failure.refused("The server sent no sign-in.") }
            token = newToken
            KeychainItem.store(newToken, service: keychainService, account: Self.tokenAccount)
            KeychainItem.store(address, service: keychainService, account: Self.emailAccount)
            if body["must_change"] as? Bool == true {
                state = .mustChangePassword(email: address)
            } else {
                state = .signedIn(email: address)
            }
        case 401: throw Failure.wrongEmailOrPassword
        case 429: throw Failure.tooManyAttempts
        default: throw Failure.refused(message(from: body, fallback: "Sign-in failed (\(status))."))
        }
    }

    /// Replaces a temporary password, and keeps this device signed in with the new session.
    public func setPassword(_ password: String) async throws {
        let (status, body) = try await send("password", body: ["password": password], authorized: true)
        switch status {
        case 200:
            guard let newToken = body["token"] as? String else { throw Failure.refused("The server sent no sign-in.") }
            token = newToken
            KeychainItem.store(newToken, service: keychainService, account: Self.tokenAccount)
            state = .signedIn(email: emailSaved())
        case 401: forget()
        default: throw Failure.refused(message(from: body, fallback: "Couldn't change the password (\(status))."))
        }
    }

    public func signOut() {
        let old = token
        forget()
        guard let old else { return }
        // Best effort: the local session is already gone whether or not the server hears.
        Task { [serverURL, session] in
            var request = URLRequest(url: serverURL.appendingPathComponent("api/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(old)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: request)
        }
    }

    /// Called when a library download is refused: the session is no longer good.
    public func expire() {
        if token != nil { forget() }
    }

    /// Adds this account's bearer token to a library request.
    public func authorize(_ request: URLRequest) -> URLRequest {
        guard let bearerToken else { return request }
        var request = request
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Private

    private func forget() {
        token = nil
        KeychainItem.store(nil, service: keychainService, account: Self.tokenAccount)
        KeychainItem.store(nil, service: keychainService, account: Self.emailAccount)
        state = .signedOut
    }

    private func emailSaved() -> String {
        KeychainItem.read(service: keychainService, account: Self.emailAccount) ?? ""
    }

    private func message(from body: [String: Any], fallback: String) -> String {
        body["error"] as? String ?? fallback
    }

    /// One request to the account API. Throws `.unreachable` when there's no answer at all.
    private func send(_ path: String, body: [String: String]? = nil, authorized: Bool = false) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: serverURL.appendingPathComponent("api/\(path)"))
        request.httpMethod = body == nil ? "GET" : "POST"
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            throw Failure.unreachable
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (http.statusCode, json)
    }
}
