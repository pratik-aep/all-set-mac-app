import Foundation
import Testing
@testable import AllSetCore

/// Answers the account API from a per-test handler, so no test reaches a real server.
private final class AccountStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: Any]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Each test gets its own Keychain entry, so the real saved session is never touched.
@MainActor @Suite(.serialized) struct LibraryAccountTests {
    private func makeAccount() -> (LibraryAccount, String) {
        let service = "com.pratik.allset.library.tests.\(UUID().uuidString)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountStubProtocol.self]
        let account = LibraryAccount(serverURL: URL(string: "http://library.test:8080/")!,
                                     keychainService: service,
                                     session: URLSession(configuration: configuration))
        return (account, service)
    }

    private func forget(_ service: String) {
        KeychainItem.store(nil, service: service, account: "session")
        KeychainItem.store(nil, service: service, account: "email")
    }

    @Test func signingInSavesTheSessionAndAttachesItToRequests() async throws {
        let (account, service) = makeAccount()
        defer { forget(service) }
        AccountStubProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://library.test:8080/api/login")
            return (200, ["token": "tok-123", "must_change": false])
        }
        try await account.signIn(email: "Friend@Example.com ", password: "pw")
        #expect(account.state == .signedIn(email: "friend@example.com"))
        #expect(account.bearerToken == "tok-123")

        let plain = URLRequest(url: URL(string: "http://library.test:8080/live/a.mp4")!)
        #expect(account.authorize(plain).value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")

        let reopened = LibraryAccount(serverURL: URL(string: "http://library.test:8080/")!, keychainService: service,
                                      session: URLSession(configuration: .ephemeral))
        #expect(reopened.state == .signedIn(email: "friend@example.com"))
    }

    @Test func aWrongPasswordSaysSoAndSignsNothingIn() async {
        let (account, service) = makeAccount()
        defer { forget(service) }
        AccountStubProtocol.handler = { _ in (401, ["error": "wrong email or password"]) }
        await #expect(throws: LibraryAccount.Failure.wrongEmailOrPassword) {
            try await account.signIn(email: "friend@example.com", password: "nope")
        }
        #expect(account.state == .signedOut)
        #expect(account.bearerToken == nil)
    }

    @Test func atTemporaryPasswordTheAppAsksForANewOne() async throws {
        let (account, service) = makeAccount()
        defer { forget(service) }
        AccountStubProtocol.handler = { request in
            if request.url?.path == "/api/login" { return (200, ["token": "temp", "must_change": true]) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer temp")
            return (200, ["token": "fresh"])
        }
        try await account.signIn(email: "friend@example.com", password: "temporary")
        #expect(account.state == .mustChangePassword(email: "friend@example.com"))
        #expect(account.bearerToken == nil)  // nothing else is allowed until the password is changed
        try await account.setPassword("a-long-new-password")
        #expect(account.state == .signedIn(email: "friend@example.com"))
        #expect(account.bearerToken == "fresh")
    }

    @Test func aRefusedSessionSignsOutButAnUnreachableServerDoesNot() async throws {
        let (account, service) = makeAccount()
        defer { forget(service) }
        AccountStubProtocol.handler = { _ in (200, ["token": "t", "must_change": false]) }
        try await account.signIn(email: "friend@example.com", password: "pw")

        AccountStubProtocol.handler = { _ in (401, ["error": "sign in"]) }
        await account.verify()
        #expect(account.state == .signedOut)

        AccountStubProtocol.handler = { _ in (200, ["token": "t", "must_change": false]) }
        try await account.signIn(email: "friend@example.com", password: "pw")
        AccountStubProtocol.handler = nil  // no answer at all: the saved session is kept
        await account.verify()
        #expect(account.state == .signedIn(email: "friend@example.com"))
    }

    @Test func signingOutForgetsTheSession() async throws {
        let (account, service) = makeAccount()
        defer { forget(service) }
        AccountStubProtocol.handler = { _ in (200, ["token": "t", "must_change": false]) }
        try await account.signIn(email: "friend@example.com", password: "pw")
        account.signOut()
        #expect(account.state == .signedOut)
        #expect(KeychainItem.read(service: service, account: "session") == nil)
    }
}
