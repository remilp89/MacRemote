import Foundation

public enum MouseButton: String, Codable {
    case left, right
}

/// Flags de modificateurs (valeurs brutes de CGEventFlags, volontairement dupliquées
/// pour que le code iOS n'ait pas besoin d'importer CoreGraphics).
public enum ModFlag {
    public static let shift: UInt64 = 0x0002_0000
    public static let control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000
    public static let command: UInt64 = 0x0010_0000
}

/// Codes de touches virtuelles macOS (indépendants de la disposition clavier).
public enum MacKey {
    public static let `return`: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
}

public enum Message: Codable {
    /// Premier message après la poignée de main TLS. `pairing` = appairage via le code.
    case hello(pairing: Bool, deviceName: String)
    /// Réponse : identifiant + clé secrète (hex) à réutiliser pour les connexions suivantes.
    case welcome(tokenId: String, key: String, hostName: String)
    /// Erreur à afficher (arrête aussi le retour d'écran côté iPhone).
    case notice(String)
    /// Information non bloquante.
    case info(String)
    case mouseMove(dx: Double, dy: Double)
    /// Position absolue normalisée (0…1) sur l'écran principal.
    case mouseAbs(x: Double, y: Double)
    case mouseButton(MouseButton, down: Bool)
    /// Un clic complet ; `count` = numéro du clic dans la série (1 = simple, 2 = double…)
    case click(MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case key(code: UInt16, down: Bool, flags: UInt64)
    /// Texte à taper tel quel (Unicode).
    case text(String)
    /// Raccourci : caractères résolus via la disposition clavier du Mac, avec modificateurs.
    case chord(text: String, flags: UInt64)
    case screenStart(maxWidth: Int, fps: Int, quality: Double)
    case screenStop
    /// Presse-papiers (texte) : iPhone → Mac, demande Mac → iPhone, et réponse.
    case clipboardSet(String)
    case clipboardGet
    case clipboard(String)
    /// Envoi d'un fichier iPhone → Mac (dossier Téléchargements/MacRemote).
    case fileStart(name: String, size: Int)
    case fileChunk(Data)
    case fileEnd
    /// Image JPEG de l'écran du Mac.
    case frame(jpeg: Data, width: Int, height: Int)
}

/// Découpage des messages : 4 octets (longueur, big-endian) + JSON.
public struct Framer {
    private var buffer = Data()
    public init() {}

    public static func encode(_ message: Message) -> Data? {
        guard let body = try? JSONEncoder().encode(message) else { return nil }
        var len = UInt32(body.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(body)
        return out
    }

    public mutating func feed(_ data: Data) -> [Message] {
        buffer.append(data)
        var out: [Message] = []
        while buffer.count >= 4 {
            let s = buffer.startIndex
            let len = buffer[s..<s + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if len > 16_000_000 { buffer.removeAll(); break }
            let total = 4 + Int(len)
            guard buffer.count >= total else { break }
            let body = buffer.subdata(in: s + 4..<s + total)
            buffer.removeSubrange(s..<s + total)
            if let m = try? JSONDecoder().decode(Message.self, from: body) { out.append(m) }
        }
        return out
    }
}

public let serviceType = "_macremote._tcp"
/// Port TCP fixe (connexion directe par adresse IP, ex. via Tailscale).
public let defaultPort: UInt16 = 52525
