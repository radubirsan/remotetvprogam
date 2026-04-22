import Foundation

/// Accepts Samsung TVs' self-signed certificate for `wss://<ip>:8002` sessions.
///
/// Scoped to the session created for the TV connection — never attached to `URLSession.shared`,
/// so the trust bypass cannot leak into unrelated traffic. Not App Store safe; fine for a POC.
final class SamsungTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
