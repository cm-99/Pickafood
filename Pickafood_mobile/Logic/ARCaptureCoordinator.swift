import Foundation
import ARKit
import SceneKit
import UIKit
import CoreImage

struct CapturePayload {
    let image: UIImage
    let depthURL: URL?          // 16-bit PNG (mm)
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let resolution: CGSize
    let lidarAvailable: Bool
}

final class ARCaptureCoordinator: NSObject, ARSCNViewDelegate {
    private let sceneView: ARSCNView
    private var hasDelivered = false
    var onCapture: ((CapturePayload) -> Void)?
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
        super.init()
        self.sceneView.delegate = self
        self.sceneView.scene = SCNScene()
        self.sceneView.automaticallyUpdatesLighting = false
    }

    deinit{stopSession()}
    
    func deliverOnce(_ payload: CapturePayload) {
        guard !hasDelivered else { return }
        hasDelivered = true
        onCapture?(payload)
    }
    
    static var lidarSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    func startSession() {
        hasDelivered = false
        let cfg = ARWorldTrackingConfiguration()
        if Self.lidarSupported {
            cfg.frameSemantics.insert(.sceneDepth)
            cfg.frameSemantics.insert(.smoothedSceneDepth)
        }
        cfg.worldAlignment = .gravity
        sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func stopSession() { sceneView.session.pause() }
    
    private func exifOrientation(for ui: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch ui {
        case .portrait:            return .right      // obrót +90°
        case .portraitUpsideDown:  return .left       // obrót -90°
        case .landscapeLeft:       return .up         // brak obrotu
        case .landscapeRight:      return .down       // obrót 180°
        default:                   return .right
        }
    }

    private enum RotationKind { case none, cw90, ccw90, r180 }

    private func rotationKind(for ui: UIInterfaceOrientation) -> RotationKind {
        switch ui {
        case .portrait:            return .cw90
        case .portraitUpsideDown:  return .ccw90
        case .landscapeLeft:       return .none
        case .landscapeRight:      return .r180
        default:                   return .cw90
        }
    }

    private func remapIntrinsics(fx: Double, fy: Double, cx: Double, cy: Double,
                                 inW: Int, inH: Int,
                                 rot: RotationKind) -> (fx: Double, fy: Double, cx: Double, cy: Double, outW: Int, outH: Int)
    {
        switch rot {
        case .none:
            return (fx, fy, cx, cy, inW, inH)
        case .r180:
            let cxp = Double(inW - 1) - cx
            let cyp = Double(inH - 1) - cy
            return (fx, fy, cxp, cyp, inW, inH)
        case .cw90: // W' = H, H' = W
            let fxp = fy
            let fyp = fx
            let cxp = Double(inH - 1) - cy
            let cyp = cx
            return (fxp, fyp, cxp, cyp, inH, inW)
        case .ccw90: // W' = H, H' = W
            let fxp = fy
            let fyp = fx
            let cxp = cy
            let cyp = Double(inW - 1) - cx
            return (fxp, fyp, cxp, cyp, inH, inW)
        }
    }

    func capture(_ completion: @escaping (Result<CapturePayload, Error>) -> Void) {
        guard let frame = sceneView.session.currentFrame else {
            completion(.failure(NSError(domain: "ARCapture", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Brak aktualnej klatki AR"])))
            return
        }

        let pb = frame.capturedImage
        let inW = CVPixelBufferGetWidth(pb)
        let inH = CVPixelBufferGetHeight(pb)
        let ciRaw = CIImage(cvPixelBuffer: pb)

        let uiOrientation = sceneView.window?.windowScene?.interfaceOrientation ?? .portrait
        let exif = exifOrientation(for: uiOrientation)
        let rot = rotationKind(for: uiOrientation)

        let ciOriented = ciRaw.oriented(forExifOrientation: Int32(exif.rawValue))
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ciOriented, from: ciOriented.extent) else {
            completion(.failure(NSError(domain: "ARCapture", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Nie udało się zbudować CGImage"])))
            return
        }
        let rgbUpright = UIImage(cgImage: cg, scale: 1.0, orientation: .up)
        let outW = Int(ciOriented.extent.width)
        let outH = Int(ciOriented.extent.height)

        let K = frame.camera.intrinsics
        let fx0 = Double(K.columns.0.x)
        let fy0 = Double(K.columns.1.y)
        let cx0 = Double(K.columns.2.x)
        let cy0 = Double(K.columns.2.y)

        let (fx, fy, cx, cy, _, _) = remapIntrinsics(fx: fx0, fy: fy0, cx: cx0, cy: cy0,
                                                     inW: inW, inH: inH, rot: rot)

        var depthURL: URL? = nil
        if let depth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            do {
                depthURL = try DepthWriter.write16bitPNG(
                    from: depth.depthMap,
                    cropInRGBSpace: CGRect(x: 0, y: 0, width: inW, height: inH),
                    rgbSize: CGSize(width: inW, height: inH),
                    orientation: exif
                )
            } catch {
                print("[ARCapture] Depth save error:", error)
            }
        }

        let payload = CapturePayload(
            image: rgbUpright,
            depthURL: depthURL,
            fx: fx, fy: fy, cx: cx, cy: cy,
            resolution: CGSize(width: outW, height: outH),
            lidarAvailable: (frame.smoothedSceneDepth ?? frame.sceneDepth) != nil
        )
        completion(.success(payload))
    }
}
