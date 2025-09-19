import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    let onCodeScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permissionGranted = false

    var body: some View {
        NavigationStack {
            ZStack {
                if permissionGranted {
                    #if targetEnvironment(simulator)
                    // Simulator fallback
                    VStack(spacing: 20) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        Text("Barcode Scanner")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Camera not available in simulator")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("For testing: tap button below to simulate a scan")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Simulate Scan") {
                            onCodeScanned("YAMA-TS-001") // Test SKU
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    #else
                    BarcodeScannerViewRepresentable { code in
                        onCodeScanned(code)
                    }
                    #endif
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("Camera access is required to scan barcodes")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Button("Grant Permission") {
                            requestCameraPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            print("DEBUG: BarcodeScannerView appeared")
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("DEBUG: Camera permission status: \(status.rawValue)")

        switch status {
        case .authorized:
            print("DEBUG: Camera authorized")
            permissionGranted = true
        case .notDetermined:
            print("DEBUG: Camera permission not determined, requesting...")
            requestCameraPermission()
        case .denied, .restricted:
            print("DEBUG: Camera permission denied/restricted")
            permissionGranted = false
        @unknown default:
            print("DEBUG: Camera permission unknown")
            permissionGranted = false
        }
    }

    private func requestCameraPermission() {
        print("DEBUG: Requesting camera permission...")
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                print("DEBUG: Camera permission granted: \(granted)")
                permissionGranted = granted
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable for Camera

struct BarcodeScannerViewRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Camera Controller

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession?.isRunning == true {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.stopRunning()
            }
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .qr, .code128, .code39, .code93]
        } else {
            failed()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Add overlay with scanning area
        addScanningOverlay()

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func addScanningOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Create a clear rectangle in the middle for scanning area
        let scanRect = CGRect(
            x: view.bounds.width * 0.1,
            y: view.bounds.height * 0.3,
            width: view.bounds.width * 0.8,
            height: view.bounds.height * 0.2
        )

        let path = UIBezierPath(rect: overlayView.bounds)
        let scanPath = UIBezierPath(rect: scanRect)
        path.append(scanPath.reversing())

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer

        view.addSubview(overlayView)

        // Add border around scan area
        let borderView = UIView(frame: scanRect)
        borderView.layer.borderColor = UIColor.white.cgColor
        borderView.layer.borderWidth = 2
        borderView.layer.cornerRadius = 8
        view.addSubview(borderView)

        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Position barcode within the frame"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.frame = CGRect(
            x: 20,
            y: scanRect.maxY + 20,
            width: view.bounds.width - 40,
            height: 30
        )
        view.addSubview(instructionLabel)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            // Provide haptic feedback
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            // Stop the session and call the completion handler
            captureSession.stopRunning()
            onCodeScanned?(stringValue)
        }
    }

    private func failed() {
        let alert = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from this app.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        captureSession = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}

#if DEBUG
struct BarcodeScannerView_Previews: PreviewProvider {
    static var previews: some View {
        BarcodeScannerView { code in
            print("Scanned: \(code)")
        }
    }
}
#endif