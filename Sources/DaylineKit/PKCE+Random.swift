import CryptoKit
import DaylineCore
import Foundation

extension PKCE {
    static func random() -> PKCE {
        let verifier = randomURLSafeString(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

func randomURLSafeString(byteCount: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64URLEncodedString()
}
