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
}
