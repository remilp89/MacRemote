import Foundation
import Network
import UIKit

enum ScreenQuality: String, CaseIterable {
    case eco = "Économie", normal = "Normal", high = "Haute"
    /// (largeur max, images/s, qualité JPEG)
    var params: (Int, Int, Double) {
        switch self {
        case .eco: return (960, 10, 0.4)
        case .normal: return (1280, 20, 0.5)
        case .high: return (1920, 30, 0.7)
        }
    }
}

final class RemoteClient: ObservableObject {
    struct Host: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }
    enum State: Equatable {
        case idle
        case connecting
        case connected(String)
        case failed(String)
    }

    @Published var hosts: [Host] = []
    @Published var state: State = .idle
    @Published var screenImage: UIImage?
    @Published var notice: String?
    @Published var banner: String?
    @Published var transfer: Double?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var framer = Framer()
    private var currentHost: Host?
    private var pairing = false
    private var wantsScreen = false

    private var pendingDX = 0.0, pendingDY = 0.0
    private var moveScheduled = false

    /// Hôte saisi à la main : « adresse » ou « adresse:port » (ex. IP Tailscale).
    static func manualHost(_ text: String) -> Host? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", maxSplits: 1).map(String.init)
        let port = parts.count == 2 ? UInt16(parts[1]) : defaultPort
        guard let port, let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        return Host(name: t, endpoint: .hostPort(host: NWEndpoint.Host(parts[0]), port: nwPort))
    }

    // MARK: Découverte

    func startBrowsing() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [Host] = results.compactMap {
                if case let .service(name, _, _, _) = $0.endpoint { return Host(name: name, endpoint: $0.endpoint) }
                return nil
            }
            DispatchQueue.main.async { self?.hosts = found.sorted { $0.name < $1.name } }
        }
        b.start(queue: .main)
        browser = b
    }

    // MARK: Connexion

    func hasToken(for host: Host) -> Bool { Keychain.get("token.\(host.name)") != nil }

    /// `code` = code d'appairage (première connexion) ; sinon on utilise la clé mémorisée.
    func connect(to host: Host, code: String?) {
        disconnect()
        let psk: (identity: String, key: Data)
        if let code, !Auth.normalize(code).isEmpty {
            psk = (Auth.pairIdentity, Auth.pairKey(code: code))
            pairing = true
        } else if let saved = Keychain.get("token.\(host.name)"),
                  case let parts = saved.split(separator: ":").map(String.init), parts.count == 2,
                  let key = Auth.fromHex(parts[1]) {
            psk = ("t:" + parts[0], key)
            pairing = false
        } else {
            state = .failed("Appairage nécessaire")
            return
        }
        currentHost = host
        state = .connecting
        framer = Framer()

        let c = NWConnection(to: host.endpoint, using: Auth.parameters(psks: [psk]))
        connection = c
        c.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                guard let self, self.connection === c else { return }
                switch st {
                case .ready:
                    self.send(.hello(pairing: self.pairing, deviceName: UIDevice.current.name))
                case .failed:
                    self.fail(self.pairing ? "Code incorrect ou Mac injoignable" : "Connexion refusée (Mac réinitialisé ? Appaire à nouveau)")
                case .waiting(let e):
                    if case .connecting = self.state, case .tls = e { self.fail("Échec TLS (code incorrect ?)") }
                case .cancelled:
                    break
                default: break
                }
            }
        }
        c.start(queue: .main)
        receive(c)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.connection === c, self.state == .connecting else { return }
            self.fail(self.pairing ? "Code incorrect ou Mac injoignable" : "Mac injoignable")
        }
    }

    private func fail(_ msg: String) {
        if !pairing, let h = currentHost, msg.hasPrefix("Connexion refusée") { Keychain.delete("token.\(h.name)") }
        connection?.cancel()
        connection = nil
        screenImage = nil
        state = .failed(msg)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        screenImage = nil
        wantsScreen = false
        state = .idle
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self, self.connection === c else { return }
            if let data { for m in self.framer.feed(data) { self.handle(m) } }
            if done || error != nil {
                if case .connected = self.state { self.fail("Connexion perdue") }
            } else {
                self.receive(c)
            }
        }
    }

    private func handle(_ m: Message) {
        switch m {
        case let .welcome(tokenId, key, hostName):
            if !tokenId.isEmpty, let h = currentHost { Keychain.set("\(tokenId):\(key)", for: "token.\(h.name)") }
            state = .connected(hostName)
        case let .notice(text):
            notice = text
            wantsScreen = false
        case let .info(text):
            showBanner(text)
        case let .clipboard(text):
            UIPasteboard.general.string = text
            showBanner(text.isEmpty ? "Presse-papiers du Mac vide" : "Presse-papiers du Mac copié")
        case let .frame(jpeg, _, _):
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                guard let img = UIImage(data: jpeg)?.preparingForDisplay() else { return }
                DispatchQueue.main.async { if self?.wantsScreen == true { self?.screenImage = img } }
            }
        default: break
        }
    }

    // MARK: Envoi

    func send(_ m: Message) {
        guard let data = Framer.encode(m) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func move(dx: Double, dy: Double) {
        pendingDX += dx; pendingDY += dy
        guard !moveScheduled else { return }
        moveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
            guard let self else { return }
            self.moveScheduled = false
            let (x, y) = (self.pendingDX, self.pendingDY)
            self.pendingDX = 0; self.pendingDY = 0
            if x != 0 || y != 0 { self.send(.mouseMove(dx: x, dy: y)) }
        }
    }

    func showBanner(_ text: String) {
        banner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.banner == text { self?.banner = nil } }
    }

    func setScreen(_ on: Bool, quality: ScreenQuality = .normal) {
        wantsScreen = on
        let p = quality.params
        if on { send(.screenStart(maxWidth: p.0, fps: p.1, quality: p.2)) }
        else { send(.screenStop); screenImage = nil }
    }

    // MARK: Presse-papiers et fichiers

    func sendClipboard() {
        guard let t = UIPasteboard.general.string, !t.isEmpty else { showBanner("Presse-papiers de l'iPhone vide"); return }
        send(.clipboardSet(t))
    }

    func requestClipboard() { send(.clipboardGet) }

    /// Envoi par morceaux, chacun attendant la fin du précédent (pas de saturation mémoire).
    func sendFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let self, let fh = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? fh.close() }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            self.sendAndWait(.fileStart(name: url.lastPathComponent, size: size))
            var sent = 0
            while let chunk = try? fh.read(upToCount: 256 * 1024), !chunk.isEmpty {
                self.sendAndWait(.fileChunk(chunk))
                sent += chunk.count
                let p = Double(sent) / Double(max(size, 1))
                DispatchQueue.main.async { self.transfer = p }
            }
            self.sendAndWait(.fileEnd)
            DispatchQueue.main.async { self.transfer = nil }
        }
    }

    private func sendAndWait(_ m: Message) {
        guard let data = Framer.encode(m) else { return }
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            guard let c = self.connection else { sem.signal(); return }
            c.send(content: data, completion: .contentProcessed { _ in sem.signal() })
        }
        sem.wait()
    }
}
