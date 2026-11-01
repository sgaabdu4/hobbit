import Foundation
import Security

final class Backend: NSObject, URLSessionDelegate {
    static let shared = Backend()
    private struct Configuration: Decodable {
        let serverURL: URL
        let deviceSecret: String
        let certificate: Data
    }
    private let configuration: Configuration?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    override init() {
        configuration = Bundle.main.url(forResource: "DevelopmentConfig", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) }
        super.init()
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let configuration else { throw AuthFailure.invalid("This build is not paired with a server. Run the device setup and rebuild.") }
        var request = URLRequest(url: configuration.serverURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = path == "pets" ? 190 : 35
        request.setValue("Bearer " + configuration.deviceSecret, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            reportConnection(code: 0)
        } catch {
            reportConnection(code: (error as NSError).code)
            throw error
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthFailure.invalid("The server returned an unreadable response. Try again.")
        }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw AuthFailure.invalid(result["error"] as? String ?? "The server could not complete that request. Try again.")
        }
        return result
    }

    private func reportConnection(code: Int) {
        let report: [String: Any] = ["transportErrorCode": code, "updatedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("network-check.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let configuration, challenge.protectionSpace.host == configuration.serverURL.host,
              let trust = challenge.protectionSpace.serverTrust,
              let pinned = SecCertificateCreateWithData(nil, configuration.certificate as CFData) else {
            reportTrust(stage: "challenge_rejected", code: 0)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        SecTrustSetAnchorCertificates(trust, [pinned] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            reportTrust(stage: "certificate_validation_failed", code: error.map(CFErrorGetCode) ?? 0)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
              SecCertificateCopyData(leaf) as Data == configuration.certificate else {
            reportTrust(stage: "certificate_pin_mismatch", code: 0)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        reportTrust(stage: "verified", code: 0)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func reportTrust(stage: String, code: Int) {
        let report: [String: Any] = ["stage": stage, "errorCode": code]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("trust-check.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
