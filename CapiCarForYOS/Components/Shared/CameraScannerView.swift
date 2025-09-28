import SwiftUI
import AVFoundation
import Vision
import AudioToolbox

// MARK: - Camera Scanner View

struct CameraScannerView: View {
    @StateObject private var scanner = VisionBarcodeScanner()
    @Environment(\.dismiss) private var dismiss
    
    let onScanResult: (String) -> Void
    let onScanError: (String) -> Void
    
    @State private var showingPermissionDenied = false
    @State private var scanFeedback = ScanFeedback()
    @State private var showSuccessAnimation = false
    @State private var showErrorAnimation = false
    @State private var hasAppeared = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(scanner: scanner)
                .ignoresSafeArea()
            
            // Scanner overlay
            scannerOverlay
            
            // Scan result overlay
            if scanner.isScanning {
                scanningIndicator
            }
            
            // Success animation overlay
            if showSuccessAnimation {
                successFeedbackOverlay
            }
            
            // Error animation overlay
            if showErrorAnimation {
                errorFeedbackOverlay
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("DEBUG: CameraScannerView appeared")
            if !hasAppeared {
                hasAppeared = true
                startScanning()
            }
        }
        .onDisappear {
            print("DEBUG: CameraScannerView disappeared")
            scanner.stopScanning()
        }
        .onChange(of: scanner.lastScanResult) { _, newResult in
            if let result = newResult {
                handleScanResult(result)
            }
        }
        .onChange(of: scanner.scanError) { _, error in
            if let error = error {
                handleScanError(error)
            }
        }
        .alert("Camera Permission Required", isPresented: $showingPermissionDenied) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Please allow camera access in Settings to scan barcodes")
        }
    }
    
    // MARK: - Subviews
    
    private var scannerOverlay: some View {
        VStack {
            // Top controls
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                // Flashlight toggle
                Button(action: { scanner.toggleFlashlight() }) {
                    Image(systemName: scanner.isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            .padding()
            
            Spacer()
            
            // Scanning area frame
            scanningFrame
            
            Spacer()
            
            // Bottom instructions
            instructionsText
        }
    }
    
    private var scanningFrame: some View {
        ZStack {
            // Scanning frame
            RoundedRectangle(cornerRadius: 12)
                .stroke(scanner.isScanning ? Color.green : Color.white, lineWidth: 3)
                .frame(width: 280, height: 200)
                .overlay(
                    // Corner brackets
                    VStack {
                        HStack {
                            scannerCorner
                            Spacer()
                            scannerCorner.rotationEffect(.degrees(90))
                        }
                        Spacer()
                        HStack {
                            scannerCorner.rotationEffect(.degrees(-90))
                            Spacer()
                            scannerCorner.rotationEffect(.degrees(180))
                        }
                    }
                    .padding(8)
                )
            
            // Animated scanning line
            if scanner.isScanning {
                scanningLine
            }
        }
    }
    
    private var scannerCorner: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(scanner.isScanning ? Color.green : Color.white, lineWidth: 4)
        .frame(width: 20, height: 20)
    }
    
    private var scanningLine: some View {
        Rectangle()
            .fill(Color.green.opacity(0.8))
            .frame(height: 2)
            .frame(width: 260)
            .offset(y: scanFeedback.scanLineOffset)
            .animation(
                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: scanFeedback.scanLineOffset
            )
            .onAppear {
                scanFeedback.startScanLineAnimation()
            }
    }
    
    private var scanningIndicator: some View {
        VStack {
            Spacer()
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Scanning...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
            .padding(.bottom, 100)
        }
    }
    
    private var instructionsText: some View {
        VStack(spacing: 8) {
            Text("Position barcode within frame")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Ensure good lighting and steady hands")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 50)
    }
    
    private var successFeedbackOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .scaleEffect(showSuccessAnimation ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.3), value: showSuccessAnimation)
            
            Text("Scan Successful!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showSuccessAnimation = false
            }
        }
    }
    
    private var errorFeedbackOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
                .scaleEffect(showErrorAnimation ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.3), value: showErrorAnimation)
            
            Text("Scan Failed")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Please try again")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showErrorAnimation = false
            }
        }
    }
    
    // MARK: - Actions
    
    private func startScanning() {
        print("DEBUG: Starting camera scanning process...")
        Task {
            print("DEBUG: Requesting camera permission...")
            let granted = await scanner.requestCameraPermission()
            print("DEBUG: Camera permission granted: \(granted)")
            
            if granted {
                print("DEBUG: Starting scanner...")
                scanner.startScanning()
            } else {
                print("DEBUG: Camera permission denied")
                showingPermissionDenied = true
            }
        }
    }
    
    private func handleScanResult(_ result: String) {
        // Validate the barcode format
        let validationResult = scanner.validateBarcodeFormat(result)
        
        switch validationResult {
        case .valid(_):
            // Show success animation
            showSuccessAnimation = true
            
            // Provide success haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Provide audio feedback (system sound)
            AudioServicesPlaySystemSound(SystemSoundID(1057)) // Camera shutter sound
            
            // Brief pause for animation, then process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onScanResult(result)
                dismiss()
            }
            
        case .invalid(let reason):
            // Show error animation
            showErrorAnimation = true
            
            // Provide error haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
            
            // Show error to user
            handleScanError("Invalid barcode: \(reason)")
        }
    }
    
    private func handleScanError(_ error: String) {
        // Show error animation if not already showing
        if !showErrorAnimation {
            showErrorAnimation = true
        }
        
        // Provide error haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
        
        onScanError(error)
    }
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let scanner: VisionBarcodeScanner
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        // Set up a timer to check for preview layer availability
        DispatchQueue.main.async {
            self.setupPreviewLayer(in: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Check if preview layer exists and update frame
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        } else {
            // Try to add preview layer if it became available
            setupPreviewLayer(in: uiView)
        }
    }
    
    private func setupPreviewLayer(in view: UIView) {
        guard let previewLayer = scanner.previewLayer,
              view.layer.sublayers?.contains(where: { $0 is AVCaptureVideoPreviewLayer }) != true else {
            return
        }
        
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
}

// MARK: - Scan Feedback Helper

class ScanFeedback: ObservableObject {
    @Published var scanLineOffset: CGFloat = -90
    
    func startScanLineAnimation() {
        withAnimation {
            scanLineOffset = 90
        }
    }
}

// MARK: - Preview
#if DEBUG
struct CameraScannerView_Previews: PreviewProvider {
    static var previews: some View {
        CameraScannerView(
            onScanResult: { result in
                print("Scanned: \(result)")
            },
            onScanError: { error in
                print("Scan error: \(error)")
            }
        )
    }
}
#endif
