import SwiftUI
import ARKit
import SceneKit

struct ARCaptureView: UIViewRepresentable {
    let onCaptured: (CapturePayload) -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject {
        var coord: ARCaptureCoordinator?
        private var isCapturing = false

        func attach(to view: ARSCNView) {
            coord = ARCaptureCoordinator(sceneView: view)
            coord?.startSession()
        }

        func stop() { coord?.stopSession() }

        func takePhoto(onCaptured: @escaping (CapturePayload)->Void, onCancel: @escaping ()->Void) {
            guard let coord, !isCapturing else { return }
            isCapturing = true
            coord.capture { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let p):
                    coord.deliverOnce(p)
                    onCaptured(p)
                    coord.stopSession()
                case .failure:
                    onCancel()
                }
                self.isCapturing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARCaptureScreen: View {
    @Environment(\.dismiss) private var dismiss
    let onCaptured: (CapturePayload) -> Void

    @State private var lidarIsOn = ARCaptureCoordinator.lidarSupported

    var body: some View {
        ZStack(alignment: .bottom) {
            ARSCNViewContainer { payload in
                onCaptured(payload)
                dismiss()
            } onCancel: {
                dismiss()
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    LidarBadge(available: lidarIsOn)
                        .padding(.leading, 12).padding(.top, 12)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)

            HStack {
                Button("Anuluj") { dismiss() }
                    .padding(10)
                    .background(.ultraThinMaterial).cornerRadius(10)
                Spacer()
                ShutterButton {
                    NotificationCenter.default.post(name: .arCaptureFire, object: nil)
                }
            }
            .padding()
            .background(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom))
        }
        .onAppear { lidarIsOn = ARCaptureCoordinator.lidarSupported }
    }
}

struct LidarBadge: View {
    let available: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: available ? "point.3.connected.trianglepath.dotted" : "eye.slash")
            Text(available ? "LiDAR ON" : "LiDAR OFF")
        }
        .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
        .background(available ? Color.green.opacity(0.9) : Color.gray.opacity(0.7))
        .foregroundColor(.white)
        .clipShape(Capsule())
        .shadow(radius: 2)
    }
}

struct ShutterButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(Color.white).frame(width: 72, height: 72)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 2))
        }
    }
}

private struct ARSCNViewContainer: UIViewControllerRepresentable {
    let onCaptured: (CapturePayload)->Void
    let onCancel: ()->Void

    final class CaptureHostVC: UIViewController {
        var onCaptured: ((CapturePayload)->Void)!
        var onCancel: (() -> Void)!
        private var coord: ARCaptureCoordinator!
        private var fireToken: NSObjectProtocol?
        private var isCapturing = false

        override func viewDidLoad() {
            super.viewDidLoad()
            let view = ARSCNView(frame: .zero)
            self.view = view

            coord = ARCaptureCoordinator(sceneView: view)
            coord.startSession()

            fireToken = NotificationCenter.default.addObserver(
                forName: .arCaptureFire, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, !self.isCapturing else { return }
                self.isCapturing = true
                self.coord.capture { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let p):
                        self.coord.deliverOnce(p)  
                        self.onCaptured(p)
                        self.teardown()
                    case .failure:
                        self.onCancel()
                        self.isCapturing = false
                    }
                }
            }
        }

        private func teardown() {
            if let fireToken { NotificationCenter.default.removeObserver(fireToken) }
            fireToken = nil
            coord?.stopSession()
        }

        deinit { teardown() }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            teardown()
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = CaptureHostVC()
        vc.onCaptured = onCaptured
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension Notification.Name { static let arCaptureFire = Notification.Name("ar.capture.fire") }
