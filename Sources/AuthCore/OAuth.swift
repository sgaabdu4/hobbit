import Foundation
import CryptoKit
import Security

enum AuthFailure: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}

struct OAuthAttempt {
    let state: String
    let nonce: String
    let verifier: String
    let redirect: URL
    let clientID: String?
    let hostID: String

    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthFailure.invalid("Could not prepare secure sign-in. Try again.")
        }
        return Data(bytes).base64URL
    }

    func authorizationURL() -> URL {
        var fields = [
            "client_id": clientID ?? "dynamic_agent_client",
            "ext_agent_host_id": hostID,
            "response_type": "code",
            "redirect_uri": redirect.absoluteString,
            "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
            "resource": "https://api.openai.com/v1",
            "state": state, "nonce": nonce,
            "code_challenge_method": "S256",
            "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        ]
        if clientID == nil { fields["agent_name_hint"] = "Habitaker" }
        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }

    func callback(_ url: URL) throws -> (code: String, clientID: String) {
        guard url.scheme == redirect.scheme, url.host == redirect.host,
              url.port == redirect.port, url.path == redirect.path,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw AuthFailure.invalid("Sign-in returned to the wrong address. Try again.")
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var fields: [String: String] = [:]
        for item in items {
            guard fields[item.name] == nil, let value = item.value else {
                throw AuthFailure.invalid("Sign-in returned an invalid response. Try again.")
            }
            fields[item.name] = value
        }
        guard fields["state"] == state else {
            throw AuthFailure.invalid("Sign-in could not be matched to this attempt. Try again.")
        }
        if fields["error"] != nil {
            throw AuthFailure.invalid("ChatGPT did not authorize this sign-in. You can try again.")
        }
        guard let issued = fields["client_id"] ?? clientID,
              issued.hasPrefix("oaiapp_"), issued.count > 7,
              clientID == nil || issued == clientID,
              let code = fields["code"], !code.isEmpty else {
            throw AuthFailure.invalid("ChatGPT registration did not complete. Try again.")
        }
        return (code, issued)
    }
}

struct TokenResponse: Codable {
    let id_token: String
    let access_token: String
    let refresh_token: String?
    let token_type: String
    let scope: String
    let expires_in: Int
}

struct JWKSet: Decodable {
    struct Key: Decodable {
        let kty: String
        let kid: String
        let alg: String?
        let use: String?
        let n: String?
        let e: String?
    }
    let keys: [Key]
}

enum IDTokenValidator {
    static func validate(_ token: String, keys: JWKSet, clientID: String, nonce: String,
                         now: Date = Date()) throws -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URL: parts[0]),
              let payload = Data(base64URL: parts[1]),
              let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String,
              let key = keys.keys.first(where: { $0.kid == kid && $0.kty == "RSA" }),
              key.alg == nil || key.alg == "RS256", key.use == nil || key.use == "sig",
              let n = key.n.flatMap({ Data(base64URL: $0) }),
              let e = key.e.flatMap({ Data(base64URL: $0) }), !n.isEmpty, !e.isEmpty else {
            throw AuthFailure.invalid("ChatGPT identity signature could not be checked.")
        }
        let der = sequence(integer(n) + integer(e))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                       kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data("\(parts[0]).\(parts[1])".utf8) as CFData,
                                    signature as CFData, &error) else {
            throw AuthFailure.invalid("ChatGPT identity signature was not valid.")
        }
        guard let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              claims["iss"] as? String == "https://auth.openai.com",
              let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970,
              claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw AuthFailure.invalid("ChatGPT identity checks failed. Try signing in again.")
        }
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audience.contains(clientID),
              audience.count <= 1 || claims["azp"] as? String == clientID,
              claims["azp"] == nil || claims["azp"] as? String == clientID else {
            throw AuthFailure.invalid("ChatGPT identity was issued for another app.")
        }
        if let before = claims["nbf"] as? Double, before > now.timeIntervalSince1970 + 30 {
            throw AuthFailure.invalid("ChatGPT identity is not valid yet. Check the phone clock.")
        }
        return subject
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 { bytes.insert(UInt8(value & 255), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    private static func integer(_ data: Data) -> Data {
        var value = Data(data.drop(while: { $0 == 0 }))
        if value.isEmpty { value = Data([0]) }
        if value.first! & 0x80 != 0 { value.insert(0, at: 0) }
        return Data([0x02]) + length(value.count) + value
    }
    private static func sequence(_ data: Data) -> Data {
        Data([0x30]) + length(data.count) + data
    }
}
