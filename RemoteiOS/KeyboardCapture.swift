import SwiftUI
import UIKit

/// Vue invisible, toujours first responder : reçoit le clavier logiciel (texte, retour arrière)
/// et le clavier physique (flèches, F1–F12, raccourcis ⌘/⌃/⌥).
final class KeyCaptureView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onKey: ((UInt16, UInt64) -> Void)?
    var onChord: ((String, UInt64) -> Void)?

    private let emptyInput = UIView(frame: .zero)
    var softKeyboard = false {
        didSet { if oldValue != softKeyboard { reloadInputViews() } }
    }
    private var repeatTimer: Timer?

    override var canBecomeFirstResponder: Bool { true }
    // Sans clavier logiciel, on fournit une vue de saisie vide pour ne rien afficher.
    override var inputView: UIView? { softKeyboard ? nil : emptyInput }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { DispatchQueue.main.async { _ = self.becomeFirstResponder() } }
    }

    // UIKeyInput
    var hasText: Bool { true }
    func insertText(_ text: String) { onText?(text) }
    func deleteBackward() { onDelete?() }

    // UITextInputTraits
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default

    // MARK: Clavier physique

    private static let hidToMac: [UIKeyboardHIDUsage: UInt16] = {
        var m: [UIKeyboardHIDUsage: UInt16] = [
            .keyboardLeftArrow: MacKey.left, .keyboardRightArrow: MacKey.right,
            .keyboardDownArrow: MacKey.down, .keyboardUpArrow: MacKey.up,
            .keyboardEscape: MacKey.escape, .keyboardTab: MacKey.tab,
            .keyboardDeleteOrBackspace: MacKey.delete, .keyboardReturnOrEnter: MacKey.return,
            .keyboardDeleteForward: 117, .keyboardHome: 115, .keyboardEnd: 119,
            .keyboardPageUp: 116, .keyboardPageDown: 121,
        ]
        let f: [UIKeyboardHIDUsage] = [.keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6,
                                       .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12]
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (k, c) in zip(f, codes) { m[k] = c }
        return m
    }()

    private func macFlags(_ f: UIKeyModifierFlags) -> UInt64 {
        (f.contains(.shift) ? ModFlag.shift : 0) | (f.contains(.control) ? ModFlag.control : 0) |
        (f.contains(.alternate) ? ModFlag.option : 0) | (f.contains(.command) ? ModFlag.command : 0)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for p in presses {
            guard let key = p.key else { rest.insert(p); continue }
            let flags = macFlags(key.modifierFlags)
            if let code = Self.hidToMac[key.keyCode] {
                onKey?(code, flags)
                startRepeat { [weak self] in self?.onKey?(code, flags) }
            } else if flags & (ModFlag.command | ModFlag.control | ModFlag.option) != 0, !key.charactersIgnoringModifiers.isEmpty {
                onChord?(key.charactersIgnoringModifiers, flags)
            } else {
                rest.insert(p)   // texte normal : traité par insertText
            }
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeat(); super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeat(); super.pressesCancelled(presses, with: event)
    }

    private func startRepeat(_ fire: @escaping () -> Void) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in fire() }
        }
    }
    private func stopRepeat() { repeatTimer?.invalidate(); repeatTimer = nil }
}

struct KeyboardCapture: UIViewRepresentable {
    var softKeyboard: Bool
    var onText: (String) -> Void
    var onDelete: () -> Void
    var onKey: (UInt16, UInt64) -> Void
    var onChord: (String, UInt64) -> Void

    func makeUIView(context: Context) -> KeyCaptureView { KeyCaptureView() }

    func updateUIView(_ v: KeyCaptureView, context: Context) {
        v.onText = onText; v.onDelete = onDelete; v.onKey = onKey; v.onChord = onChord
        v.softKeyboard = softKeyboard
    }
}
