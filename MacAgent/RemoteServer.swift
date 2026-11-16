import Foundation
import Network
import CoreGraphics

/// Une connexion iPhone.
final class Session {
    let connection: NWConnection
    var framer = Framer()
    var authenticated = false
    var deviceName = "iPhone"
    var wantsScreen = false
    var framesInFlight = 0
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
            let l = try NWListener(using: Auth.parameters(psks: psks))
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
        guard sessions[id] != nil else { return }
        sessions[id] = nil
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
        case .screenStart:
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                s.send(.notice("Autorise l'enregistrement d'écran pour MacRemote Agent (Réglages Système > Confidentialité), puis relance l'agent et réessaie."))
                return
            }
            s.wantsScreen = true
            updateCapture(params: m)
        case .screenStop:
            s.wantsScreen = false
            updateCapture()
        default: break
        }
    }

    // MARK: Capture d'écran

    private func updateCapture(params: Message? = nil) {
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
            if case let .screenStart(w, fps)? = params { cap.start(maxWidth: w, fps: fps) }
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
}
