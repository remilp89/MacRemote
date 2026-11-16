import SwiftUI

struct ContentView: View {
    @EnvironmentObject var client: RemoteClient
    @State private var pinHost: RemoteClient.Host?
    @State private var pin = ""

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

    private var hostList: some View {
        NavigationStack {
            List {
                Section("Macs détectés") {
                    if client.hosts.isEmpty {
                        HStack { ProgressView(); Text("Recherche en cours…").foregroundColor(.secondary) }
                    }
                    ForEach(client.hosts) { h in
                        Button {
                            if client.hasToken(for: h) { client.connect(to: h, code: nil) }
                            else { pinHost = h }
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(h.name)
                                Spacer()
                                if client.state == .connecting { ProgressView() }
                            }
                        }
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

    private var flags: UInt64 {
        (shift ? ModFlag.shift : 0) | (ctrl ? ModFlag.control : 0) | (opt ? ModFlag.option : 0) | (cmd ? ModFlag.command : 0)
    }
    private func clearMods() { shift = false; ctrl = false; opt = false; cmd = false }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(hostName, systemImage: "desktopcomputer").font(.headline)
                Spacer()
                Button { screenOn.toggle(); client.setScreen(screenOn) } label: { Image(systemName: screenOn ? "display" : "display.trianglebadge.exclamationmark") }
                    .font(.title2)
                if screenOn {
                    Button { direct.toggle() } label: { Image(systemName: direct ? "hand.point.up.left.fill" : "hand.point.up.left") }
                        .font(.title2)
                }
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
