import AuthenticationServices
import Combine
import Foundation
import Network
import UIKit

@MainActor
final class AuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var message = "Sign in to meet your AI habit companion."
    @Published var busy = false
    @Published var verified = false
    @Published var planEnabled = false
    private var listener: NWListener?
    private var session: ASWebAuthenticationSession?
    private var attempt: OAuthAttempt?
    private var timeout: Task<Void, Never>?
    private var exchange: Task<Void, Never>?
    private var stage = "not_started"

    struct Registration: Codable {
        let clientID: String
        let subject: String
        let tokens: TokenResponse
        var nonce: String? = nil
    }

    override init() {
        super.init()
        restoreSavedSession()
        if !verified { Task { await refreshIfNeeded() } }
    }

    private func restoreSavedSession() {
        guard let data = try? Keychain.read("registration"),
              let saved = try? JSONDecoder().decode(Registration.self, from: data) else { return }
        let parts = saved.tokens.id_token.split(separator: ".")
        guard parts.count == 3, let payload = Data(base64URL: String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let expiry = claims["exp"] as? Double,
              claims["sub"] as? String == saved.subject else { return }
        guard expiry > Date().timeIntervalSince1970 + 60 else { return }
        verified = true
        planEnabled = saved.tokens.scope.split(separator: " ").contains("chatgpt.tokens.use.direct")
        record("identity_verified", "Your saved ChatGPT sign-in is ready.")
    }

    func refreshIfNeeded() async {
        if !verified { restoreSavedSession() }
        guard !busy, let data = try? Keychain.read("registration"),
              let saved = try? JSONDecoder().decode(Registration.self, from: data),
              let previous = Self.claims(saved.tokens.id_token),
              let expiry = previous["exp"] as? Double,
              expiry <= Date().timeIntervalSince1970 + 60 else { return }
        guard let refreshToken = saved.tokens.refresh_token else {
            verified = false
            message = "Your sign-in expired. Continue with ChatGPT to reconnect."
            return
        }
        busy = true
        defer { busy = false }
        record("refreshing", "Reconnecting your ChatGPT sign-in...")
        do {
            let fields = ["grant_type": "refresh_token", "client_id": saved.clientID, "refresh_token": refreshToken,
                          "resource": "https://api.openai.com/v1"]
            var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            request.httpBody = Data(fields.sorted { $0.key < $1.key }.map {
                $0.key + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
            }.joined(separator: "&").utf8)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            let network = URLSession(configuration: config)
            defer { network.invalidateAndCancel() }
            let (data, response) = try await network.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AuthFailure.invalid("ChatGPT could not renew this session. Continue with ChatGPT to reconnect.")
            }
            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty,
                  tokens.expires_in > 0, tokens.refresh_token?.isEmpty == false else {
                throw AuthFailure.invalid("ChatGPT returned incomplete renewal details. Sign in again.")
            }
            let (keyData, keyResponse) = try await network.data(from: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
            guard (keyResponse as? HTTPURLResponse)?.statusCode == 200 else { throw AuthFailure.invalid("ChatGPT identity checks are unavailable. Try again.") }
            let keys = try JSONDecoder().decode(JWKSet.self, from: keyData)
            let originalNonce = saved.nonce ?? previous["nonce"] as? String
            let returnedNonce = Self.claims(tokens.id_token)?["nonce"] as? String
            if let returnedNonce, returnedNonce != originalNonce { throw AuthFailure.invalid("The renewed identity did not match this sign-in.") }
            let expectedNonce = returnedNonce == nil ? nil : originalNonce
            let subject = try IDTokenValidator.validate(tokens.id_token, keys: keys, clientID: saved.clientID, nonce: expectedNonce)
            guard subject == saved.subject else { throw AuthFailure.invalid("The renewed identity did not match your saved account.") }
            try Keychain.save(JSONEncoder().encode(Registration(clientID: saved.clientID, subject: subject, tokens: tokens, nonce: originalNonce)), account: "registration")
            verified = true
            planEnabled = tokens.scope.split(separator: " ").contains("chatgpt.tokens.use.direct")
            record("identity_verified", "Your ChatGPT sign-in was renewed securely.")
        } catch {
            verified = false
            record("refresh_failed", error is URLError ? "Cannot reconnect right now. Check Wi-Fi, then continue with ChatGPT." : error.localizedDescription)
        }
    }

    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = Data(base64URL: String(parts[1])) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func signIn() {
        guard !busy else { return }
        busy = true
        verified = false
        planEnabled = false
        record("preparing", "Preparing secure sign-in.")
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.busy else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener?.port else { return }
                        do { try self.openBrowser(port: port.rawValue) }
                        catch { self.fail(error.localizedDescription) }
                    case .failed: self.fail("The iPhone could not start its sign-in callback. Try again.")
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.receive(connection, buffered: Data()) }
            }
            listener.start(queue: .main)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { return }
                self?.fail("Sign-in timed out. Tap Continue with ChatGPT to try again.")
            }
        } catch { fail(error.localizedDescription) }
    }

    private func openBrowser(port: UInt16) throws {
        let hostID: String
        if let saved = try Keychain.read("host"), let value = String(data: saved, encoding: .utf8) {
            hostID = value
        } else {
            hostID = "urn:uuid:" + UUID().uuidString.lowercased()
            try Keychain.save(Data(hostID.utf8), account: "host")
        }
        let registration = try Keychain.read("registration").map { try JSONDecoder().decode(Registration.self, from: $0) }
        let attempt = OAuthAttempt(state: try OAuthAttempt.random(), nonce: try OAuthAttempt.random(),
                                   verifier: try OAuthAttempt.random(),
                                   redirect: URL(string: "http://127.0.0.1:\(port)/auth/callback")!,
                                   clientID: registration?.clientID, hostID: hostID)
        self.attempt = attempt
        let session = ASWebAuthenticationSession(url: attempt.authorizationURL(), callback: .customScheme("habitaker-auth")) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.attempt != nil else { return }
                if error != nil { self.fail("Sign-in was closed. Tap Continue with ChatGPT to try again.") }
            }
        }
        session.presentationContextProvider = self
        self.session = session
        guard session.start() else { throw AuthFailure.invalid("The iPhone could not open secure sign-in. Try again.") }
        record("browser_open", "Finish signing in with OpenAI. This screen will update when it returns.")
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        if buffered.isEmpty { connection.start(queue: .main) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let bytes = buffered + (data ?? Data())
                guard bytes.count <= 16_384, error == nil else { connection.cancel(); return }
                guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.receive(connection, buffered: bytes) }
                    return
                }
                let line = text.components(separatedBy: "\r\n")[0].split(separator: " ").map(String.init)
                guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/auth/callback?"),
                      let pending = self.attempt,
                      let url = URL(string: "http://127.0.0.1:\(pending.redirect.port!)" + line[1]) else {
                    self.respond(connection, status: "404 Not Found", headers: "", body: "Not found.")
                    return
                }
                do {
                    let result = try pending.callback(url)
                    self.attempt = nil
                    self.respond(connection, status: "302 Found", headers: "Location: habitaker-auth://complete\r\n", body: "Return to Hobbit.")
                    self.listener?.cancel()
                    self.listener = nil
                    self.record("callback_received", "OpenAI returned to your iPhone. Checking your identity.")
                    self.exchange = Task {
                        do { try await self.exchangeCode(result.code, clientID: result.clientID, pending: pending) }
                        catch { self.fail(error.localizedDescription) }
                    }
                } catch {
                    self.respond(connection, status: "400 Bad Request", headers: "", body: "Sign-in could not be verified. Close this page and try again.")
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, headers: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\n\(headers)Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func exchangeCode(_ code: String, clientID: String, pending: OAuthAttempt) async throws {
        let fields = ["grant_type": "authorization_code", "client_id": clientID, "code": code,
                      "code_verifier": pending.verifier, "redirect_uri": pending.redirect.absoluteString,
                      "resource": "https://api.openai.com/v1"]
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map {
            $0.key + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AuthFailure.invalid("OpenAI token exchange failed (HTTP \(status)). Sign-in is not verified.")
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty, tokens.expires_in > 0 else {
            throw AuthFailure.invalid("OpenAI returned incomplete credentials. Sign-in is not verified.")
        }
        record("token_received", "Checking OpenAI's signed identity.")
        let (keyData, keyResponse) = try await network.data(from: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
        guard (keyResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthFailure.invalid("OpenAI's identity verification keys are unavailable. Try again.")
        }
        let keys = try JSONDecoder().decode(JWKSet.self, from: keyData)
        let subject = try IDTokenValidator.validate(tokens.id_token, keys: keys, clientID: clientID, nonce: pending.nonce)
        if let existing = try Keychain.read("registration") {
            let original = try JSONDecoder().decode(Registration.self, from: existing)
            guard original.subject == subject, original.clientID == clientID else {
                throw AuthFailure.invalid("This sign-in used a different account. The saved account was not changed.")
            }
        }
        try Task.checkCancellation()
        try Keychain.save(JSONEncoder().encode(Registration(clientID: clientID, subject: subject, tokens: tokens, nonce: pending.nonce)), account: "registration")
        verified = true
        planEnabled = tokens.scope.split(separator: " ").contains("chatgpt.tokens.use.direct")
        busy = false
        timeout?.cancel()
        session = nil
        record("identity_verified", "ChatGPT sign-in verified on this iPhone. Next: your Hobbit pet and voice call.")
    }

    private func fail(_ message: String) {
        attempt = nil
        listener?.cancel()
        listener = nil
        session?.cancel()
        session = nil
        timeout?.cancel()
        exchange?.cancel()
        busy = false
        record("failed", message)
    }

    private func record(_ stage: String, _ message: String) {
        self.stage = stage
        self.message = message
        let record: [String: Any] = ["stage": stage, "identityVerified": verified,
                                     "chatGPTPlanPermission": planEnabled,
                                     "petSource": "app_specific_generation_planned",
                                     "updatedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            let directory = URL.documentsDirectory
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("verification.json"), options: [.atomic, .completeFileProtection])
        } catch { self.message += " Local test report could not be saved." }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
