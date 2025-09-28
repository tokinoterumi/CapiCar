import Foundation
@preconcurrency import AVFoundation
import Vision
import UIKit

// MARK: - Vision Barcode Scanner

@MainActor
class VisionBarcodeScanner: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isScanning = false
    @Published var lastScanResult: String?
    @Published var scanError: String?
    @Published var isFlashlightOn = false
    
    // MARK: - Camera Properties
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayerInternal: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    // MARK: - Vision Properties
    
    // Vision request will be created on each scan
    private var lastScanTime: Date = Date()
    private let scanCooldown: TimeInterval = 1.0 // Prevent duplicate scans
    
    // MARK: - Public Properties
    
    var previewLayer: AVCaptureVideoPreviewLayer? {
        return previewLayerInternal
    }
    
    // MARK: - Camera Permission
    
    func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Scanning Control
    
    func startScanning() {
        guard !isScanning else { return }
        
        Task { [weak self] in
            guard let self = self else { return }
            await self.setupCaptureSession()
        }
    }
    
    func stopScanning() {
        Task { [weak self] in
            guard let self = self else { return }
            let session = self.captureSession
            
            await withCheckedContinuation { continuation in
                self.sessionQueue.async {
                    session?.stopRunning()
                    continuation.resume()
                }
            }
            
            self.isScanning = false
        }
    }
    
    func toggleFlashlight() {
        Task { [weak self] in
            guard let self = self else { return }
            
            enum FlashlightResult {
                case success(Bool)
                case failure(String)
            }
            
            let result: FlashlightResult = await withCheckedContinuation { continuation in
                self.sessionQueue.async {
                    guard let device = AVCaptureDevice.default(for: .video),
                          device.hasTorch else { 
                        continuation.resume(returning: .failure("No flashlight available"))
                        return 
                    }
                    
                    do {
                        try device.lockForConfiguration()
                        
                        let wasOff = device.torchMode == .off
                        if wasOff {
                            try device.setTorchModeOn(level: 1.0)
                        } else {
                            device.torchMode = .off
                        }
                        
                        device.unlockForConfiguration()
                        continuation.resume(returning: .success(wasOff))
                        
                    } catch {
                        continuation.resume(returning: .failure("Failed to toggle flashlight: \(error.localizedDescription)"))
                    }
                }
            }
            
            switch result {
            case .success(let wasOff):
                self.isFlashlightOn = !wasOff
            case .failure(let errorMessage):
                self.scanError = errorMessage
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCaptureSession() async {
        // Prevent multiple setup calls
        guard captureSession == nil else { 
            print("DEBUG: Capture session already exists")
            return 
        }
        
        print("DEBUG: Setting up capture session...")
        
        let session = AVCaptureSession()
        
        // Check if device is available
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("DEBUG: No camera device available")
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Camera not available on this device"
            }
            return
        }
        
        // Try to create input
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
            print("DEBUG: Video input created successfully")
        } catch {
            print("DEBUG: Failed to create video input: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Failed to access camera: \(error.localizedDescription)"
            }
            return
        }
        
        // Configure session for optimal barcode scanning
        session.beginConfiguration()
        session.sessionPreset = .high
        print("DEBUG: Session configuration started")
        
        // Add video input
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            print("DEBUG: Video input added successfully")
        } else {
            print("DEBUG: Cannot add video input to session")
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Failed to add video input"
            }
            session.commitConfiguration()
            return
        }
        
        // Configure video output
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        print("DEBUG: Video output configured")
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            print("DEBUG: Video output added successfully")
        } else {
            print("DEBUG: Cannot add video output to session")
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Failed to add video output"
            }
            session.commitConfiguration()
            return
        }
        
        // Configure camera settings for better barcode detection
        configureCameraSettings(device: videoDevice)
        print("DEBUG: Camera settings configured")
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        print("DEBUG: Preview layer created")
        
        session.commitConfiguration()
        print("DEBUG: Session configuration committed")
        
        // Store references
        self.captureSession = session
        self.videoOutput = output
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.previewLayerInternal = previewLayer
            self.isScanning = true
            print("DEBUG: Scanner state updated on main thread")
        }
        
        // Start the session
        print("DEBUG: Starting capture session...")
        session.startRunning()
        print("DEBUG: Capture session started")
    }
    
    private func configureCameraSettings(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            // Enable auto focus if available
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            // Enable auto exposure if available
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Enable auto white balance if available
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            // Set appropriate frame rate for barcode scanning
            if let videoConnection = device.activeFormat.videoSupportedFrameRateRanges.first {
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(min(30, videoConnection.maxFrameRate)))
            }
            
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Failed to configure camera: \(error.localizedDescription)"
            }
        }
    }
    
    private func processBarcode(_ observation: VNBarcodeObservation) {
        guard let barcodeValue = observation.payloadStringValue else { return }
        
        // Check scan cooldown to prevent duplicate scans
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= scanCooldown else { return }
        lastScanTime = now
        
        DispatchQueue.main.async {
            self.lastScanResult = barcodeValue
        }
    }
    
    // MARK: - Cleanup
    
    private nonisolated func cleanupResources() {
        // Use MainActor.assumeIsolated since we know this is safe during deinit
        // The object is being deallocated so no other code can access these properties
        MainActor.assumeIsolated {
            let session = self.captureSession
            let output = self.videoOutput
            
            sessionQueue.async {
                // Clean up video output delegate
                output?.setSampleBufferDelegate(nil, queue: nil)
                
                // Stop capture session
                session?.stopRunning()
                
                // Turn off flashlight - check all devices
                guard let device = AVCaptureDevice.default(for: .video),
                      device.hasTorch else { return }
                
                do {
                    try device.lockForConfiguration()
                    if device.torchMode != .off {
                        device.torchMode = .off
                    }
                    device.unlockForConfiguration()
                } catch {
                    print("Failed to turn off flashlight in cleanup: \(error)")
                }
            }
        }
    }
    
    deinit {
        print("DEBUG: VisionBarcodeScanner deinit called")
        cleanupResources()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VisionBarcodeScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create Vision request handler
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // Create barcode request with completion handler
        let barcodeRequest = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { [weak self] in
                    self?.scanError = "Barcode detection failed: \(error.localizedDescription)"
                }
                return
            }
            
            guard let observations = request.results as? [VNBarcodeObservation] else { return }
            
            // Process the first valid barcode found
            for observation in observations {
                if observation.confidence > 0.5 { // Only process high-confidence results
                    Task { @MainActor in
                        self.processBarcode(observation)
                    }
                    break
                }
            }
        }
        
        // Configure barcode request for multiple symbologies
        barcodeRequest.symbologies = [
            .ean13,
            .ean8,
            .upce,
            .code128,
            .code39,
            .code93,
            .itf14,
            .dataMatrix,
            .qr,
            .pdf417,
            .aztec,
            .codabar
        ]
        
        // Perform the request
        do {
            try requestHandler.perform([barcodeRequest])
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.scanError = "Vision request failed: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
        // This is called when the system is under heavy load
        print("Frame dropped during barcode scanning")
    }
}

// MARK: - Barcode Validation Extensions

extension VisionBarcodeScanner {
    
    /// Validates if a scanned barcode matches expected format patterns
    func validateBarcodeFormat(_ barcode: String) -> BarcodeValidationResult {
        // Remove any whitespace
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's empty
        guard !cleanBarcode.isEmpty else {
            return .invalid("Empty barcode")
        }
        
        // Check for common SKU patterns
        if isValidSKUFormat(cleanBarcode) {
            return .valid(.sku)
        }
        
        // Check for UPC/EAN patterns
        if isValidUPCFormat(cleanBarcode) {
            return .valid(.upc)
        }
        
        // Check for QR code patterns (could contain JSON or URLs)
        if cleanBarcode.contains("{") || cleanBarcode.hasPrefix("http") {
            return .valid(.qrCode)
        }
        
        // Default to generic barcode if it passes basic validation
        if cleanBarcode.count >= 4 && cleanBarcode.allSatisfy({ $0.isASCII }) {
            return .valid(.generic)
        }
        
        return .invalid("Unrecognized barcode format")
    }
    
    private func isValidSKUFormat(_ barcode: String) -> Bool {
        // Common SKU patterns: ABC-123-XYZ, SKU123456, etc.
        let skuPattern = "^[A-Za-z0-9\\-_]{3,20}$"
        return barcode.range(of: skuPattern, options: .regularExpression) != nil
    }
    
    private func isValidUPCFormat(_ barcode: String) -> Bool {
        // UPC-A (12 digits), UPC-E (8 digits), EAN-13 (13 digits), EAN-8 (8 digits)
        let digits = barcode.filter { $0.isNumber }
        return [8, 12, 13].contains(digits.count) && digits == barcode
    }
}

// MARK: - Barcode Validation Models

enum BarcodeValidationResult {
    case valid(BarcodeType)
    case invalid(String)
}

enum BarcodeType {
    case sku
    case upc
    case qrCode
    case generic
    
    var displayName: String {
        switch self {
        case .sku: return "SKU"
        case .upc: return "UPC/EAN"
        case .qrCode: return "QR Code"
        case .generic: return "Barcode"
        }
    }
}
