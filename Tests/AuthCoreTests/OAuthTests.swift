import Foundation
import Testing
import Security
@testable import AuthCore

struct OAuthTests {
    let attempt = OAuthAttempt(state: "expected-state", nonce: "nonce", verifier: "verifier",
                               redirect: URL(string: "http://127.0.0.1:1455/auth/callback")!,
                               clientID: nil, hostID: "urn:uuid:test")

    @Test func registrationUsesLoopbackAndPKCE() throws {
        let url = attempt.authorizationURL()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        #expect(url.host == "auth.openai.com")
        #expect(fields["client_id"] == "dynamic_agent_client")
        #expect(fields["redirect_uri"] == attempt.redirect.absoluteString)
        #expect(fields["code_challenge_method"] == "S256")
        #expect(fields["code_challenge"] != attempt.verifier)
        #expect(fields["agent_name_hint"] == "Habitaker")
    }

    @Test func callbackAcceptsIssuedClient() throws {
        let result = try attempt.callback(URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&code=one-use&client_id=oaiapp_test")!)
        #expect(result.clientID == "oaiapp_test")
        #expect(result.code == "one-use")
    }

    @Test(arguments: [
        "http://127.0.0.1:1455/auth/callback?state=wrong&code=x&client_id=oaiapp_test",
        "http://localhost:1455/auth/callback?state=expected-state&code=x&client_id=oaiapp_test",
        "http://127.0.0.1:1456/auth/callback?state=expected-state&code=x&client_id=oaiapp_test",
        "http://127.0.0.1:1455/auth/callback?state=expected-state&state=expected-state&code=x&client_id=oaiapp_test",
        "http://127.0.0.1:1455/auth/callback?state=expected-state&code=x&client_id=dynamic_agent_client",
        "http://127.0.0.1:1455/auth/callback?state=expected-state&error=access_denied&code=x&client_id=oaiapp_test",
        "http://127.0.0.1:1455/auth/callback?state=expected-state&code=x"
    ])
    func rejectsInvalidCallback(value: String) {
        #expect(throws: AuthFailure.self) { try attempt.callback(URL(string: value)!) }
    }

    @Test func rejectsClientReplacement() {
        let returning = OAuthAttempt(state: attempt.state, nonce: attempt.nonce, verifier: attempt.verifier,
                                     redirect: attempt.redirect, clientID: "oaiapp_original", hostID: attempt.hostID)
        #expect(throws: AuthFailure.self) {
            try returning.callback(URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&code=x&client_id=oaiapp_different")!)
        }
    }

    @Test func rejectsUnsignedIdentity() throws {
        let header = Data("{\"alg\":\"none\",\"kid\":\"test\"}".utf8).base64URL
        let payload = Data("{}".utf8).base64URL
        let keys = try JSONDecoder().decode(JWKSet.self, from: Data("{\"keys\":[]}".utf8))
        #expect(throws: AuthFailure.self) {
            try IDTokenValidator.validate(header + "." + payload + ".", keys: keys, clientID: "oaiapp_test", nonce: "nonce")
        }
    }

    @Test func verifiesSignatureAndRejectsInvalidClaims() throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                       kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let representation = try #require(SecKeyCopyExternalRepresentation(publicKey, &error)) as Data
        var outer = DERReader(bytes: Array(representation))
        var inner = DERReader(bytes: Array(try outer.read(tag: 0x30)))
        let modulus = try inner.read(tag: 0x02)
        let exponent = try inner.read(tag: 0x02)
        let keyJSON: [String: Any] = ["keys": [["kty": "RSA", "kid": "test", "alg": "RS256",
                                                "n": modulus.base64URL, "e": exponent.base64URL]]]
        let keys = try JSONDecoder().decode(JWKSet.self, from: JSONSerialization.data(withJSONObject: keyJSON))
        let now = Date()
        let claims: [String: Any] = ["iss": "https://auth.openai.com", "aud": "oaiapp_test",
                                     "exp": now.timeIntervalSince1970 + 600,
                                     "sub": "test-subject", "nonce": "test-nonce"]
        let header = Data("{\"alg\":\"RS256\",\"kid\":\"test\"}".utf8).base64URL
        func sign(_ values: [String: Any]) throws -> String {
            let payload = try JSONSerialization.data(withJSONObject: values).base64URL
            let message = header + "." + payload
            let signature = try #require(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                               Data(message.utf8) as CFData, &error)) as Data
            return message + "." + signature.base64URL
        }
        let valid = try sign(claims)
        #expect(try IDTokenValidator.validate(valid, keys: keys, clientID: "oaiapp_test", nonce: "test-nonce", now: now) == "test-subject")
        for (name, value) in [("iss", "https://other.example" as Any), ("aud", "oaiapp_other" as Any),
                              ("nonce", "wrong" as Any), ("exp", now.timeIntervalSince1970 - 1 as Any),
                              ("nbf", now.timeIntervalSince1970 + 300 as Any)] {
            var changed = claims
            changed[name] = value
            let invalid = try sign(changed)
            #expect(throws: AuthFailure.self) {
                try IDTokenValidator.validate(invalid, keys: keys, clientID: "oaiapp_test", nonce: "test-nonce", now: now)
            }
        }
        let parts = valid.split(separator: ".").map(String.init)
        let altered = parts[0] + "." + Data("{}".utf8).base64URL + "." + parts[2]
        #expect(throws: AuthFailure.self) {
            try IDTokenValidator.validate(altered, keys: keys, clientID: "oaiapp_test", nonce: "test-nonce", now: now)
        }
    }
}

private struct DERReader {
    let bytes: [UInt8]
    var cursor = 0
    mutating func read(tag: UInt8) throws -> Data {
        guard cursor + 2 <= bytes.count, bytes[cursor] == tag else {
            throw AuthFailure.invalid("Test key has an invalid DER tag.")
        }
        cursor += 1
        var length = Int(bytes[cursor])
        cursor += 1
        if length & 128 != 0 {
            let count = length & 127
            guard count > 0, count <= 4, cursor + count <= bytes.count else {
                throw AuthFailure.invalid("Test key has an invalid DER length.")
            }
            length = 0
            for _ in 0..<count { length = length * 256 + Int(bytes[cursor]); cursor += 1 }
        }
        guard cursor + length <= bytes.count else { throw AuthFailure.invalid("Test key is truncated.") }
        defer { cursor += length }
        return Data(bytes[cursor..<(cursor + length)])
    }
}
