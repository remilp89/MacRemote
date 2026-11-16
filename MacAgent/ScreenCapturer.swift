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

    var isRunning: Bool { stream != nil || starting }

    func start(maxWidth: Int, fps: Int) {
        guard !isRunning else { return }
        starting = true
        Task {
            do {
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
        starting = false
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sb), let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let image = CIImage(cvPixelBuffer: pb)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = ciContext.jpegRepresentation(of: image, colorSpace: space,
                  options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.5]) else { return }
        onFrame?(jpeg, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
    }
}
