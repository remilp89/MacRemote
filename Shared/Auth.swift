import Foundation
import Network
import CryptoKit

/// Authentification et chiffrement : TLS 1.2 avec clés pré-partagées (PSK).
/// - Appairage : la clé est dérivée du code affiché sur le Mac (identité « pair »).
/// - Ensuite : clé aléatoire de 256 bits échangée pendant l'appairage (identité « t:<id> »).
enum Auth {
    static let pairIdentity = "pair"
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func randomCode() -> String {
        let chars = (0..<8).map { _ in alphabet.randomElement()! }
        return String(chars[0..<4]) + "-" + String(chars[4..<8])
    }

    static func normalize(_ code: String) -> String { code.uppercased().filter { $0.isLetter || $0.isNumber } }

    static func pairKey(code: String) -> Data {
        Data(SHA256.hash(data: Data(("macremote-pair:" + normalize(code)).utf8)))
    }

    static func randomBytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }
    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    static func fromHex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }

    static func parameters(psks: [(identity: String, key: Data)]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let o = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(o, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(o, .TLSv12)
        for suite in [TLS_DHE_PSK_WITH_AES_256_GCM_SHA384, TLS_DHE_PSK_WITH_AES_128_GCM_SHA256,
                      TLS_PSK_WITH_AES_256_GCM_SHA384, TLS_PSK_WITH_AES_128_GCM_SHA256] {
            if let s = tls_ciphersuite_t(rawValue: UInt16(suite)) { sec_protocol_options_append_tls_ciphersuite(o, s) }
        }
        for (identity, key) in psks {
            let k = key.withUnsafeBytes { DispatchData(bytes: $0) }
            let i = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(o, k as __DispatchData, i as __DispatchData)
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: tls, tcp: tcp)
        params.allowLocalEndpointReuse = true
        return params
    }
}
