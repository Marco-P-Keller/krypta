@preconcurrency import AVFoundation
import CoreImage.CIFilterBuiltins
import KryptaMessenger
import SwiftUI

/// Mein QR-Code mit frischem Einmal-Token — zeigen heißt zustimmen.
struct MyCodeView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var payload: QRPayload?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if let payload, let image = QRImage.make(payload.encoded) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(maxWidth: 300)
                        .accessibilityLabel("Dein QR-Code")
                }
                Text("Lass deinen Kontakt diesen Code mit Krypta scannen. Er gilt zehn Minuten und nur einmal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                VStack(spacing: 6) {
                    Text("Deine Kennung").font(.caption).foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = engine.userId
                        copied = true
                    } label: {
                        Label(engine.userId, systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .sensoryFeedback(.success, trigger: copied)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal)
            .navigationTitle("Mein Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: engine.userId) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Kennung teilen")
                }
            }
            .onAppear { payload = engine.myQRPayload }
        }
    }
}

enum QRImage {
    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Kamera mit QR-Erkennung. Meldet jeden Code nur einmal.
struct QRScannerView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.found = found
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var found: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var last: String?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            MainActor.assumeIsolated {
                guard code != last else { return }
                last = code
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                found?(code)
            }
        }
    }
}
