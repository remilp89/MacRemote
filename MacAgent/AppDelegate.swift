import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let server = RemoteServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MacRemote")
        server.onChange = { [weak self] in self?.rebuildMenu() }
        server.start()
        requestAccessibility(prompt: true)
        rebuildMenu()
    }

    @discardableResult
    private func requestAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Code d'appairage : \(server.code)", action: nil, keyEquivalent: "")
        let devices = server.connectedDevices
        menu.addItem(withTitle: devices.isEmpty ? "Aucun iPhone connecté" : "Connecté : " + devices.joined(separator: ", "),
                     action: nil, keyEquivalent: "")
        let addrs = ipv4Addresses()
        if !addrs.isEmpty {
            menu.addItem(withTitle: "Adresses (port \(defaultPort)) : " + addrs.joined(separator: ", "), action: nil, keyEquivalent: "")
        }
        if !AXIsProcessTrusted() {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "⚠️ Autoriser l'Accessibilité…", action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let newCode = NSMenuItem(title: "Nouveau code", action: #selector(newCode), keyEquivalent: "")
        newCode.target = self
        menu.addItem(newCode)
        let forget = NSMenuItem(title: "Oublier tous les iPhone", action: #selector(forgetAll), keyEquivalent: "")
        forget.target = self
        menu.addItem(forget)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openAccessibility() { requestAccessibility(prompt: true) }
    @objc private func newCode() { server.regenerateCode() }
    @objc private func forgetAll() { server.forgetAllDevices() }

    /// Adresses IPv4 locales (Wi-Fi, Ethernet, Tailscale…) pour la connexion directe.
    private func ipv4Addresses() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ptr.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (i.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let a = String(cString: host)
                if !a.hasPrefix("169.254") { out.append(a) }
            }
        }
        return out
    }
}
