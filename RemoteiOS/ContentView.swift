import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var client: RemoteClient
    @State private var pinHost: RemoteClient.Host?
    @State private var pin = ""
    @State private var manualText = ""
    @AppStorage("manualHosts") private var manualJoined = ""

    var body: some View {
        Group {
            if case .connected(let name) = client.state {
                ControlView(hostName: name)
            } else {
                hostList
            }
        }
        .onAppear { client.startBrowsing() }
        .alert("Code d'appairage", isPresented: Binding(get: { pinHost != nil }, set: { if !$0 { pinHost = nil } })) {
            TextField("XXXX-XXXX", text: $pin).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button("Annuler", role: .cancel) { pin = "" }
            Button("Connecter") {
                if let h = pinHost { client.connect(to: h, code: pin) }
                pin = ""
            }
        } message: {
            Text("Saisis le code affiché dans le menu MacRemote du Mac (première connexion uniquement).")
        }
    }

    private var manualList: [String] { manualJoined.split(separator: "\n").map(String.init) }

    private func addManual() {
        let t = manualText.trimmingCharacters(in: .whitespaces)
        guard RemoteClient.manualHost(t) != nil else { return }
        if !manualList.contains(t) { manualJoined = (manualList + [t]).joined(separator: "\n") }
        manualText = ""
    }

    private func open(_ h: RemoteClient.Host) {
        if client.hasToken(for: h) { client.connect(to: h, code: nil) } else { pinHost = h }
    }

    private var hostList: some View {
        NavigationStack {
            List {
                Section("Macs détectés") {
                    if client.hosts.isEmpty {
                        HStack { ProgressView(); Text("Recherche en cours…").foregroundColor(.secondary) }
                    }
                    ForEach(client.hosts) { h in
                        Button { open(h) } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(h.name)
                                Spacer()
                                if client.state == .connecting { ProgressView() }
                            }
                        }
                    }
                }
                Section("Connexion directe (IP, Tailscale…)") {
                    HStack {
                        TextField("ex. 100.64.0.5 ou 192.168.1.20", text: $manualText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button("Ajouter") { addManual() }.disabled(RemoteClient.manualHost(manualText) == nil)
                    }
                    ForEach(manualList, id: \.self) { addr in
                        if let h = RemoteClient.manualHost(addr) {
                            Button { open(h) } label: { HStack { Image(systemName: "network"); Text(addr); Spacer() } }
                        }
                    }
                    .onDelete { idx in
                        var l = manualList; l.remove(atOffsets: idx); manualJoined = l.joined(separator: "\n")
                    }
                }
                if case .failed(let msg) = client.state {
                    Section { Label(msg, systemImage: "exclamationmark.triangle").foregroundColor(.red) }
                }
            }
            .navigationTitle("MacRemote")
        }
    }
}

struct ControlView: View {
    @EnvironmentObject var client: RemoteClient
    let hostName: String
    @State private var keyboard = false
    @State private var shift = false
    @State private var ctrl = false
    @State private var opt = false
    @State private var cmd = false
    @State private var sensitivity = 1.0
    @State private var screenOn = false
    @State private var direct = true
    @State private var importing = false
    @AppStorage("screenQuality") private var qualityRaw = ScreenQuality.normal.rawValue

    private var quality: ScreenQuality { ScreenQuality(rawValue: qualityRaw) ?? .normal }

    private var flags: UInt64 {
        (shift ? ModFlag.shift : 0) | (ctrl ? ModFlag.control : 0) | (opt ? ModFlag.option : 0) | (cmd ? ModFlag.command : 0)
    }
    private func clearMods() { shift = false; ctrl = false; opt = false; cmd = false }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(hostName, systemImage: "desktopcomputer").font(.headline)
                Spacer()
                Button { screenOn.toggle(); client.setScreen(screenOn, quality: quality) } label: { Image(systemName: screenOn ? "display" : "display.trianglebadge.exclamationmark") }
                    .font(.title2)
                if screenOn {
                    Button { direct.toggle() } label: { Image(systemName: direct ? "hand.point.up.left.fill" : "hand.point.up.left") }
                        .font(.title2)
                }
                Menu {
                    Picker("Qualité de l'écran", selection: $qualityRaw) {
                        ForEach(ScreenQuality.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Button { client.sendClipboard() } label: { Label("Envoyer mon presse-papiers au Mac", systemImage: "doc.on.clipboard") }
                    Button { client.requestClipboard() } label: { Label("Récupérer le presse-papiers du Mac", systemImage: "arrow.down.doc") }
                    Button { importing = true } label: { Label("Envoyer un fichier au Mac…", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .font(.title2)
                Button { keyboard.toggle() } label: { Image(systemName: keyboard ? "keyboard.chevron.compact.down" : "keyboard") }
                    .font(.title2)
                Button("Quitter", role: .destructive) { client.disconnect() }
            }
            trackpad
            HStack {
                Image(systemName: "tortoise"); Slider(value: $sensitivity, in: 0.5...2.5); Image(systemName: "hare")
            }
            .foregroundColor(.secondary)
            keyRow
        }
        .padding()
        .background(
            KeyboardCapture(softKeyboard: keyboard, onText: typeText, onDelete: { sendKey(MacKey.delete) },
                            onKey: { code, f in client.send(.key(code: code, down: true, flags: f)); client.send(.key(code: code, down: false, flags: f)) },
                            onChord: { t, f in client.send(.chord(text: t, flags: f)) })
                .frame(width: 1, height: 1)
        )
        .onChange(of: qualityRaw) { _ in if screenOn { client.setScreen(true, quality: quality) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { client.sendFile(url) }
        }
        .overlay(alignment: .top) {
            if let b = client.transfer.map({ "Envoi du fichier… \(Int($0 * 100)) %" }) ?? client.banner {
                Text(b).font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.top, 4)
            }
        }
        .alert("MacRemote", isPresented: Binding(get: { client.notice != nil }, set: { if !$0 { client.notice = nil; screenOn = false } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(client.notice ?? "") }
    }

    @ViewBuilder private var trackpad: some View {
        if screenOn, let img = client.screenImage {
            Color.clear
                .aspectRatio(img.size.width / img.size.height, contentMode: .fit)
                .overlay(Image(uiImage: img).resizable())
                .overlay(TrackpadView(sensitivity: sensitivity, direct: direct, transparent: true))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TrackpadView(sensitivity: sensitivity)
        }
    }

    private var keyRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                modButton("⇧", $shift); modButton("⌃", $ctrl); modButton("⌥", $opt); modButton("⌘", $cmd)
                keyButton("esc", MacKey.escape); keyButton("tab", MacKey.tab); keyButton("⏎", MacKey.return)
            }
            HStack(spacing: 6) {
                keyButton("←", MacKey.left); keyButton("↑", MacKey.up); keyButton("↓", MacKey.down); keyButton("→", MacKey.right)
                keyButton("⌫", MacKey.delete)
            }
        }
    }

    private func modButton(_ label: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(label).frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(on.wrappedValue ? .accentColor : .gray)
    }

    private func keyButton(_ label: String, _ code: UInt16) -> some View {
        Button { sendKey(code) } label: { Text(label).frame(maxWidth: .infinity, minHeight: 38) }
            .buttonStyle(.bordered)
    }

    private func sendKey(_ code: UInt16) {
        client.send(.key(code: code, down: true, flags: flags))
        client.send(.key(code: code, down: false, flags: flags))
        clearMods()
    }

    private func typeText(_ t: String) {
        if t == "\n" { sendKey(MacKey.return); return }
        if flags != 0 { client.send(.chord(text: t, flags: flags)); clearMods() }
        else { client.send(.text(t)) }
    }
}
