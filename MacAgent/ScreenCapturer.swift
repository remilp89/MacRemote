import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo

/// Capture de l'écran principal via ScreenCaptureKit (macOS 12.3+), encodée en JPEG.
@available(macOS 12.3, *)
final class ScreenCapturer: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "macremote.capture")
    private var starting = false
    var onFrame: ((Data, Int, Int) -> Void)?
    var onError: ((String) -> Void)?

    private var quality = 0.5
    private var current: (Int, Int, Double)?

    var isRunning: Bool { stream != nil || starting }

    /// Démarre, ou redémarre si les réglages ont changé.
    func start(maxWidth: Int, fps: Int, quality: Double) {
        let params = (maxWidth, fps, quality)
        if isRunning, let c = current, c == params { return }
        current = params
        self.quality = quality
        let old = stream
        stream = nil
        starting = true
        Task {
            do {
                try? await old?.stopCapture()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let id = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
                    throw NSError(domain: "MacRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucun écran"])
                }
                let cfg = SCStreamConfiguration()
                let scale = min(1.0, Double(maxWidth) / Double(display.width))
                cfg.width = max(2, Int(Double(display.width) * scale))
                cfg.height = max(2, Int(Double(display.height) * scale))
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.showsCursor = true
                cfg.queueDepth = 3
                let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                stream = s
                starting = false
            } catch {
                starting = false
                DispatchQueue.main.async { self.onError?("Capture d'écran impossible : \(error.localizedDescription)") }
            }
        }
    }

    func stop() {
        let s = stream
        stream = nil
        current = nil
        starting = false
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sb), let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let image = CIImage(cvPixelBuffer: pb)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = ciContext.jpegRepresentation(of: image, colorSpace: space,
                  options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]) else { return }
        onFrame?(jpeg, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
    }
}
