import Foundation
import Network
import CoreGraphics
import AppKit

/// Une connexion iPhone.
final class Session {
    let connection: NWConnection
    var framer = Framer()
    var authenticated = false
    var deviceName = "iPhone"
    var wantsScreen = false
    var framesInFlight = 0
    var file: FileHandle?
    var filePath: URL?
    var fileExpected = 0
    var fileReceived = 0
    init(_ c: NWConnection) { connection = c }

    func send(_ m: Message, completion: (() -> Void)? = nil) {
        guard let data = Framer.encode(m) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in completion?() })
    }
}

final class RemoteServer {
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private let injector = InputInjector()
    private var failedHandshakes = 0
    private var capturerBox: AnyObject?

    private(set) var code = Auth.randomCode()
    var onChange: (() -> Void)?

    /// Jetons de confiance : [identifiant: clé hex]
    private let tokensKey = "trustedTokensV2"
    private var tokens: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: tokensKey) }
    }

    var connectedDevices: [String] { sessions.values.filter { $0.authenticated }.map { $0.deviceName } }
    var hostName: String { Host.current().localizedName ?? "Mac" }

    func regenerateCode() { code = Auth.randomCode(); failedHandshakes = 0; restartListener(); onChange?() }
    func forgetAllDevices() {
        tokens = [:]
        restartListener()
        sessions.values.forEach { $0.connection.cancel() }
    }

    func start() { restartListener() }

    private func restartListener() {
        listener?.cancel()
        var psks: [(identity: String, key: Data)] = [(Auth.pairIdentity, Auth.pairKey(code: code))]
        for (id, hex) in tokens { if let k = Auth.fromHex(hex) { psks.append(("t:" + id, k)) } }
        do {
            let params = Auth.parameters(psks: psks)
            // Port fixe pour la connexion directe par IP ; port libre en secours.
            let l: NWListener
            if let fixed = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: defaultPort)!) { l = fixed }
            else { l = try NWListener(using: params) }
            l.service = NWListener.Service(name: hostName, type: serviceType)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("Listener error: \(error)")
        }
    }

    private func accept(_ c: NWConnection) {
        let s = Session(c)
        let id = ObjectIdentifier(s)
        sessions[id] = s
        c.stateUpdateHandler = { [weak self, weak s] state in
            guard let self, let s else { return }
            switch state {
            case .failed:
                // Poignée de main TLS échouée = mauvais code / clé.
                if !s.authenticated {
                    self.failedHandshakes += 1
                    if self.failedHandshakes >= 5 { self.regenerateCode() }
                }
                self.drop(id)
            case .cancelled:
                self.drop(id)
            default: break
            }
        }
        c.start(queue: .main)
        receive(s)
    }

    private func drop(_ id: ObjectIdentifier) {
        guard let gone = sessions[id] else { return }
        sessions[id] = nil
        abortFile(gone)
        injector.releaseAll()
        updateCapture()
        onChange?()
    }

    private func receive(_ s: Session) {
        s.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak s] data, _, isComplete, error in
            guard let self, let s else { return }
            if let data, !data.isEmpty {
                for m in s.framer.feed(data) { self.handle(m, from: s) }
            }
            if isComplete || error != nil { s.connection.cancel() } else { self.receive(s) }
        }
    }

    private func handle(_ m: Message, from s: Session) {
        if !s.authenticated {
            // La poignée de main TLS a déjà prouvé la connaissance de la clé.
            guard case let .hello(pairing, name) = m else { return }
            s.deviceName = name
            s.authenticated = true
            if pairing {
                let tokenId = Auth.hex(Auth.randomBytes(4))
                let key = Auth.hex(Auth.randomBytes(32))
                tokens[tokenId] = key
                s.send(.welcome(tokenId: tokenId, key: key, hostName: hostName))
                restartListener()   // le nouveau jeton devient valide
            } else {
                s.send(.welcome(tokenId: "", key: "", hostName: hostName))
            }
            injector.rebuildLayoutMap()
            onChange?()
            return
        }
        switch m {
        case let .mouseMove(dx, dy): injector.move(dx: dx, dy: dy)
        case let .mouseAbs(x, y): injector.moveAbs(x: x, y: y)
        case let .mouseButton(b, down): injector.button(b, down: down)
        case let .click(b, count): injector.click(b, count: count)
        case let .scroll(dx, dy): injector.scroll(dx: dx, dy: dy)
        case let .key(code, down, flags): injector.key(code: code, down: down, flags: flags)
        case let .text(t): injector.type(t)
        case let .chord(t, flags): injector.chord(t, flags: flags)
        case let .screenStart(w, fps, q):
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                s.send(.notice("Autorise l'enregistrement d'écran pour MacRemote Agent (Réglages Système > Confidentialité), puis relance l'agent et réessaie."))
                return
            }
            s.wantsScreen = true
            updateCapture(params: (w, fps, q))
        case .screenStop:
            s.wantsScreen = false
            updateCapture()
        case let .clipboardSet(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            s.send(.info("Presse-papiers envoyé au Mac"))
        case .clipboardGet:
            s.send(.clipboard(NSPasteboard.general.string(forType: .string) ?? ""))
        case let .fileStart(name, size): beginFile(s, name: name, size: size)
        case let .fileChunk(data): appendFile(s, data)
        case .fileEnd: finishFile(s)
        default: break
        }
    }

    // MARK: Capture d'écran

    private func updateCapture(params: (Int, Int, Double)? = nil) {
        guard #available(macOS 12.3, *) else {
            sessions.values.filter { $0.wantsScreen }.forEach { $0.send(.notice("Retour d'écran : macOS 12.3 minimum requis.")); $0.wantsScreen = false }
            return
        }
        let anyone = sessions.values.contains { $0.wantsScreen }
        let cap = capturerBox as? ScreenCapturer ?? {
            let c = ScreenCapturer()
            c.onFrame = { [weak self] jpeg, w, h in DispatchQueue.main.async { self?.broadcast(jpeg, w, h) } }
            c.onError = { [weak self] msg in
                self?.sessions.values.filter { $0.wantsScreen }.forEach { $0.send(.notice(msg)); $0.wantsScreen = false }
            }
            capturerBox = c
            return c
        }()
        if anyone {
            if let p = params { cap.start(maxWidth: p.0, fps: p.1, quality: p.2) }
        } else {
            cap.stop()
        }
    }

    private func broadcast(_ jpeg: Data, _ w: Int, _ h: Int) {
        for s in sessions.values where s.wantsScreen && s.framesInFlight < 2 {
            s.framesInFlight += 1
            s.send(.frame(jpeg: jpeg, width: w, height: h)) { [weak s] in
                DispatchQueue.main.async { s?.framesInFlight -= 1 }
            }
        }
    }

    // MARK: Réception de fichiers

    private func beginFile(_ s: Session, name: String, size: Int) {
        abortFile(s)
        var safe = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        while safe.hasPrefix(".") { safe.removeFirst() }
        guard !safe.isEmpty, size >= 0, size <= 2_000_000_000 else { s.send(.notice("Fichier refusé")); return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("MacRemote")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent(safe)
        var n = 1
        let ext = url.pathExtension, base = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: url.path) {
            n += 1
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil), let h = try? FileHandle(forWritingTo: url) else {
            s.send(.notice("Impossible de créer le fichier sur le Mac")); return
        }
        s.file = h; s.filePath = url; s.fileExpected = size; s.fileReceived = 0
    }

    private func appendFile(_ s: Session, _ data: Data) {
        guard let h = s.file else { return }
        s.fileReceived += data.count
        if s.fileReceived > s.fileExpected { abortFile(s); s.send(.notice("Transfert interrompu (taille incorrecte)")); return }
        try? h.write(contentsOf: data)
    }

    private func finishFile(_ s: Session) {
        guard let h = s.file, let url = s.filePath else { return }
        try? h.close()
        s.file = nil; s.filePath = nil
        s.send(.info("Fichier reçu : Téléchargements/MacRemote/\(url.lastPathComponent)"))
    }

    private func abortFile(_ s: Session) {
        guard let h = s.file else { return }
        try? h.close()
        if let url = s.filePath { try? FileManager.default.removeItem(at: url) }
        s.file = nil; s.filePath = nil
    }
}
