import SwiftUI
import UIKit

/// Surface tactile façon trackpad.
/// 1 doigt : déplacer · tap : clic (double tap : double clic) · 2 doigts : défiler ·
/// tap à 2 doigts : clic droit · appui long puis glisser : cliquer-glisser.
struct TrackpadView: UIViewRepresentable {
    @EnvironmentObject var client: RemoteClient
    var sensitivity: Double
    var direct = false          // toucher direct : position absolue sur l'écran affiché
    var transparent = false     // fond transparent quand l'écran du Mac est affiché

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.clear
        v.layer.cornerRadius = 16
        v.isMultipleTouchEnabled = true
        let c = context.coordinator

        let pan1 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan1(_:)))
        pan1.minimumNumberOfTouches = 1; pan1.maximumNumberOfTouches = 1
        let pan2 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan2(_:)))
        pan2.minimumNumberOfTouches = 2; pan2.maximumNumberOfTouches = 2
        let tap1 = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap1(_:)))
        let tap2 = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap2(_:)))
        tap2.numberOfTouchesRequired = 2
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 8
        [hold, pan1].forEach { $0.delegate = c }
        [pan1, pan2, tap1, tap2, hold].forEach { v.addGestureRecognizer($0) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.sensitivity = sensitivity
        context.coordinator.direct = direct
        uiView.backgroundColor = transparent ? .clear : UIColor.secondarySystemBackground
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let client: RemoteClient
        var sensitivity = 1.0
        var direct = false
        private var lastTap = Date.distantPast
        private var tapCount = 0

        init(client: RemoteClient) { self.client = client }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

        private func abs(_ g: UIGestureRecognizer) {
            guard let v = g.view, v.bounds.width > 0, v.bounds.height > 0 else { return }
            let p = g.location(in: v)
            client.send(.mouseAbs(x: Double(p.x / v.bounds.width), y: Double(p.y / v.bounds.height)))
        }

        @objc func pan1(_ g: UIPanGestureRecognizer) {
            if direct { abs(g); return }
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            // Légère accélération : plus le geste est rapide, plus le curseur va loin.
            let mag = hypot(t.x, t.y)
            let accel = 1 + min(mag * 0.08, 2.0)
            client.move(dx: Double(t.x) * accel * sensitivity, dy: Double(t.y) * accel * sensitivity)
        }

        @objc func pan2(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            client.send(.scroll(dx: Double(t.x) * 1.5, dy: Double(t.y) * 1.5))
        }

        @objc func tap1(_ g: UITapGestureRecognizer) {
            let now = Date()
            tapCount = now.timeIntervalSince(lastTap) < 0.3 ? min(tapCount + 1, 3) : 1
            lastTap = now
            if direct { abs(g) }
            client.send(.click(.left, count: tapCount))
        }

        @objc func tap2(_ g: UITapGestureRecognizer) {
            if direct { abs(g) }
            client.send(.click(.right, count: 1)) }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                if direct { abs(g) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                client.send(.mouseButton(.left, down: true))
            case .ended, .cancelled, .failed:
                client.send(.mouseButton(.left, down: false))
            default: break
            }
        }
    }
}
