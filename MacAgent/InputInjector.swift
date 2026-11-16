import Cocoa
import Carbon

/// Injecte souris et clavier via CGEvent. Nécessite la permission Accessibilité.
final class InputInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var leftDown = false
    private var rightDown = false
    private var layoutMap: [Character: UInt16] = [:]

    init() { rebuildLayoutMap() }

    // MARK: Souris

    func move(dx: Double, dy: Double) {
        let cur = CGEvent(source: nil)?.location ?? .zero
        let target = clamp(CGPoint(x: cur.x + dx, y: cur.y + dy))
        let type: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        let button: CGMouseButton = rightDown ? .right : .left
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button) else { return }
        e.setDoubleValueField(.mouseEventDeltaX, value: dx)
        e.setDoubleValueField(.mouseEventDeltaY, value: dy)
        e.post(tap: .cghidEventTap)
    }

    /// Position absolue normalisée (0…1) sur l'écran principal.
    func moveAbs(x: Double, y: Double) {
        let r = CGDisplayBounds(CGMainDisplayID())
        let target = clamp(CGPoint(x: r.minX + min(max(x, 0), 1) * r.width, y: r.minY + min(max(y, 0), 1) * r.height))
        let type: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        let button: CGMouseButton = rightDown ? .right : .left
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    func button(_ b: MouseButton, down: Bool, clickState: Int = 1) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType
        let cgButton: CGMouseButton
        switch (b, down) {
        case (.left, true): type = .leftMouseDown; cgButton = .left; leftDown = true
        case (.left, false): type = .leftMouseUp; cgButton = .left; leftDown = false
        case (.right, true): type = .rightMouseDown; cgButton = .right; rightDown = true
        case (.right, false): type = .rightMouseUp; cgButton = .right; rightDown = false
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: pos, mouseButton: cgButton) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        e.post(tap: .cghidEventTap)
    }

    func click(_ b: MouseButton, count: Int) {
        button(b, down: true, clickState: count)
        button(b, down: false, clickState: count)
    }

    func scroll(dx: Double, dy: Double) {
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    /// Relâche tout bouton resté enfoncé (ex. déconnexion pendant un glisser).
    func releaseAll() {
        if leftDown { button(.left, down: false) }
        if rightDown { button(.right, down: false) }
    }

    // MARK: Clavier

    func key(code: UInt16, down: Bool, flags: UInt64) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        e.flags = CGEventFlags(rawValue: flags)
        e.post(tap: .cghidEventTap)
    }

    func type(_ text: String) {
        for ch in text {
            let utf16 = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                e.post(tap: .cghidEventTap)
            }
        }
    }

    /// Raccourci (ex. ⌘C) : le caractère est converti en code de touche selon la
    /// disposition clavier du Mac, pour fonctionner aussi en AZERTY.
    func chord(_ text: String, flags: UInt64) {
        for ch in text {
            let lower = Character(String(ch).lowercased())
            if let code = layoutMap[lower] {
                key(code: code, down: true, flags: flags)
                key(code: code, down: false, flags: flags)
            } else {
                type(String(ch))
            }
        }
    }

    // MARK: Helpers

    private func clamp(_ p: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        var union = CGRect.null
        for i in 0..<Int(count) { union = union.union(CGDisplayBounds(ids[i])) }
        guard !union.isNull else { return p }
        return CGPoint(x: min(max(p.x, union.minX), union.maxX - 1),
                       y: min(max(p.y, union.minY), union.maxY - 1))
    }

    func rebuildLayoutMap() {
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var map: [Character: UInt16] = [:]
        for code in 0..<128 {
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, 4, &length, &chars)
            if status == noErr, length > 0,
               let c = String(utf16CodeUnits: chars, count: length).first, map[c] == nil {
                map[c] = UInt16(code)
            }
        }
        layoutMap = map
    }
}
