import SwiftUI
@preconcurrency import AVFoundation
import Combine
import CoreImage

#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

fileprivate let sharedCIContext: CIContext = {
    let opts: [CIContextOption: Any] = [.cacheIntermediates: false]
    return CIContext(options: opts)
}()

class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var isSessionRunning = false
    @Published var isConfigured: Bool = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var videoZoomFactor: Double = 1.0 // Published per UI sync
    @Published var captureError: String?
    
    var maxZoomFactor: CGFloat {
        #if os(iOS)
        return min(device?.activeFormat.videoMaxZoomFactor ?? 5.0, 30.0)
        #else
        return 5.0
        #endif
    }

    #if canImport(UIKit)
    @Published var capturedImage: UIImage?
    #else
    @Published var capturedImage: NSImage?
    #endif
    
    @Published var lastPhotoData: Data?
    @Published var isoRange: ClosedRange<Float> = 0.0...0.0
    @Published var exposureDurationRange: ClosedRange<Double> = 0.0...0.0
    @Published var currentISO: Float = 0.0
    @Published var currentExposureDuration: Double = 0.0
    @Published var currentExposureBias: Float = 0.0

    #if canImport(UIKit)
    var lastCapturedUIImage: UIImage? { capturedImage }
    #endif

    // Simple last-known capture metadata (best-effort on iOS)
    @Published var lastISO: Int?
    @Published var lastShutter: Double?
    @Published var lastEV: Double?
    @Published var lastWhiteBalance: Int?
    @Published var lastFocal: Double?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInitiated)
    var device: AVCaptureDevice?
    private let photoOutput = AVCapturePhotoOutput()
    private var lastZoomUpdateTime: CFTimeInterval = 0
    private let zoomUpdateInterval: CFTimeInterval = 1.0 / 30.0
    
    struct CaptureOptions {
        var preferHEVC: Bool = true
        var jpegQuality: CGFloat = 0.9
        var enableStabilization: Bool = true
        var maxProcessingDimension: CGFloat = 1600
    }
    
    var captureOptions = CaptureOptions()

    override init() {
        super.init()
    }
    
    deinit {
        sessionQueue.sync { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func startSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status { self.setupCamera() }
            }
        case .denied:
            self.alert = true
        default:
            return
        }
    }
    
    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            print("[Camera] Begin setup")

            self.session.beginConfiguration()
            
            #if os(iOS)
            if self.session.canSetSessionPreset(.photo) {
                self.session.sessionPreset = .photo
            }
            #else
            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }
            #endif

            #if os(iOS)
            self.session.automaticallyConfiguresCaptureDeviceForWideColor = true
            #endif

            #if os(iOS)
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .external
            ]
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .back
            )
            #else
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            )
            #endif
            
            guard let device = discoverySession.devices.first ?? AVCaptureDevice.default(for: .video) else {
                print("[Camera] No video device available")
                self.session.commitConfiguration()
                return
            }
            self.device = device

            #if os(iOS)
            let fmt = device.activeFormat
            DispatchQueue.main.async {
                self.isoRange = fmt.minISO...fmt.maxISO
                self.exposureDurationRange = CMTimeGetSeconds(fmt.minExposureDuration)...CMTimeGetSeconds(fmt.maxExposureDuration)
                self.currentISO = device.iso
                self.currentExposureBias = device.exposureTargetBias
                self.currentExposureDuration = CMTimeGetSeconds(device.exposureDuration)
                self.lastISO = Int(exactly: NSNumber(value: device.iso)) ?? Int(device.iso)
                self.lastEV = Double(device.exposureTargetBias)
                self.lastShutter = CMTimeGetSeconds(device.exposureDuration)
                self.lastWhiteBalance = 5000
                self.lastFocal = device.lensPosition > 0 ? Double(device.lensPosition) : nil
            }
            #endif

            do {
                try device.lockForConfiguration()
                #if os(iOS)
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                #endif
                device.unlockForConfiguration()
            } catch {
                print("[Camera] Impossibile configurare il device: \(error)")
            }

            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: device)
            } catch {
                print("[Camera] Errore creazione input: \(error)")
                self.session.commitConfiguration()
                return
            }
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                #if os(iOS)
                self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = false
                #endif
                self.photoOutput.isHighResolutionCaptureEnabled = true
                if self.photoOutput.isStillImageStabilizationSupported { /* enabled per-capture if needed */ }
                if #available(iOS 13.0, *), self.photoOutput.isAppleProRAWEnabled {
                    // keep off by default; user can enable later if desired
                }
            }

            self.session.commitConfiguration()
            
            #if os(iOS)
            // Initialize zoom to the device's minimum (e.g., 0.5x on devices with ultra-wide)
            DispatchQueue.main.async {
                if let dev = self.device {
                    self.currentZoomFactor = dev.minAvailableVideoZoomFactor
                }
            }
            #endif

            if let conn = self.photoOutput.connection(with: .video) {
                conn.isEnabled = true
                if conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .auto
                }
            }

            self.startSessionIfNeeded()

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                self.isConfigured = true
            }
        }
    }
    
    func setZoom(factor: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastZoomUpdateTime >= zoomUpdateInterval else { return }
        lastZoomUpdateTime = now

        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.device else { return }
            #if os(iOS)
            do {
                try device.lockForConfiguration()
                let minZoom = device.minAvailableVideoZoomFactor
                let hardMax: CGFloat = min(device.activeFormat.videoMaxZoomFactor, 30.0)
                let finalZoom = max(minZoom, min(factor, hardMax))
                let delta = abs(device.videoZoomFactor - finalZoom)
                if delta > 0.02, device.isRampingVideoZoom {
                    // already ramping; let it finish
                } else if delta > 0.25, device.responds(to: #selector(AVCaptureDevice.ramp(toVideoZoomFactor:withRate:))) {
                    device.ramp(toVideoZoomFactor: finalZoom, withRate: 8.0)
                } else if delta > 0.005 { device.videoZoomFactor = finalZoom }
                device.unlockForConfiguration()
                DispatchQueue.main.async { 
                    self.currentZoomFactor = finalZoom
                    self.videoZoomFactor = Double(finalZoom)
                }
            } catch {
                print("[Camera] Zoom error: \(error)")
            }
            #else
            let newZoom = max(1.0, min(factor, self.maxZoomFactor))
            DispatchQueue.main.async { self.currentZoomFactor = newZoom }
            #endif
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isConfigured, self.session.isRunning else {
                print("[Camera] capturePhoto called before session ready; ignoring")
                return
            }

            let available = self.photoOutput.availablePhotoCodecTypes
            let useHEVC = available.contains(.hevc) && self.captureOptions.preferHEVC
            let settings: AVCapturePhotoSettings = useHEVC ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : (available.contains(.jpeg) ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]) : AVCapturePhotoSettings())

            settings.isHighResolutionPhotoEnabled = true
            if self.captureOptions.enableStabilization, self.photoOutput.isStillImageStabilizationSupported {
                settings.isAutoStillImageStabilizationEnabled = true
            }
            if #available(iOS 11.0, *), useHEVC {
                settings.embedsDepthDataInPhoto = false
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    private func handleCaptureError(_ error: Error) {
        let ns = error as NSError
        let code = ns.code
        let domain = ns.domain
        print("[Camera] Capture error domain=\(domain) code=\(code): \(ns.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.captureError = ns.localizedDescription
        }
        // Attempt a light-weight session restart for transient errors
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            // small delay then restart
            self.sessionQueue.asyncAfter(deadline: .now() + 0.5) {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
            }
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[Camera] Photo processing error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.handleCaptureError(error)
            }
            return
        }
        
        // Extract data on the current thread to avoid capturing non-Sendable `AVCapturePhoto` in a @Sendable closure
        guard let data = photo.fileDataRepresentation() else { return }
        let dataCopy = data // pass immutable Data into the background queue

        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            self.lastISO = Int(exactly: NSNumber(value: dev.iso)) ?? Int(dev.iso)
            self.lastShutter = CMTimeGetSeconds(dev.exposureDuration)
            self.lastEV = Double(dev.exposureTargetBias)
            self.lastWhiteBalance = 5000
            self.lastFocal = dev.lensPosition > 0 ? Double(dev.lensPosition) : nil
        }
        #endif

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let processedData = self.processCapturedImage(data: dataCopy)
            DispatchQueue.main.async {
                self.lastPhotoData = processedData
                #if canImport(UIKit)
                self.capturedImage = UIImage(data: processedData)
                #else
                if let imageRep = NSBitmapImageRep(data: processedData) {
                    let img = NSImage(size: imageRep.size)
                    img.addRepresentation(imageRep)
                    self.capturedImage = img
                }
                #endif
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            }
        }
    }
    
    private func processCapturedImage(data: Data) -> Data {
        guard let ciImage = CIImage(data: data) else { return data }

        // Optional denoise step; keep very light to preserve detail
        if let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(ciImage, forKey: kCIInputImageKey)
            noiseFilter.setValue(0.01, forKey: "inputNoiseLevel")
            noiseFilter.setValue(0.3, forKey: "inputSharpness")
            if let denoised = noiseFilter.outputImage,
               let cgImage = sharedCIContext.createCGImage(denoised, from: denoised.extent) {
                #if canImport(UIKit)
                let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                return uiImage.jpegData(compressionQuality: self.captureOptions.jpegQuality) ?? data
                #else
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: self.captureOptions.jpegQuality]) ?? data
                #endif
            }
        }
        return data
    }
}

// MARK: - Preview Views (invariate)
#if canImport(UIKit)
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = .resizeAspectFill
        
        if let device = camera.device, #available(iOS 17.0, *) {
            let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            context.coordinator.rotationCoordinator = rc
            let angle = rc.videoRotationAngleForHorizonLevelCapture
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = context.coordinator.previewLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if layer.frame != uiView.bounds { layer.frame = uiView.bounds }
            if let connection = layer.connection {
                if #available(iOS 17.0, *), let rc = context.coordinator.rotationCoordinator {
                    let angle = rc.videoRotationAngleForHorizonLevelCapture
                    if connection.isVideoRotationAngleSupported(angle) && connection.videoRotationAngle != angle {
                        connection.videoRotationAngle = angle
                    }
                } else if #unavailable(iOS 17.0) {
                    // Use legacy API only on iOS < 17
                    self.updateLegacyOrientation(for: connection, in: uiView)
                }
            }
            CATransaction.commit()
        }
    }
    
    @available(iOS, introduced: 13.0, deprecated: 17.0, message: "Use AVCaptureDevice.RotationCoordinator on iOS 17+")
    private func legacyVideoOrientation(from view: UIView) -> AVCaptureVideoOrientation {
        let orientation = view.window?.windowScene?.interfaceOrientation
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
    
    @available(iOS, introduced: 13.0, deprecated: 17.0, message: "Use AVCaptureDevice.RotationCoordinator on iOS 17+")
    private func updateLegacyOrientation(for connection: AVCaptureConnection, in view: UIView) {
        let orientation = legacyVideoOrientation(from: view)
        if connection.isVideoOrientationSupported, connection.videoOrientation != orientation {
            connection.videoOrientation = orientation
        }
    }
}
#endif

#if os(macOS)
struct CameraPreview: NSViewRepresentable {
    @ObservedObject var camera: CameraModel

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = context.coordinator.previewLayer {
            if layer.frame != nsView.bounds { layer.frame = nsView.bounds }
            layer.setAffineTransform(CGAffineTransform(scaleX: camera.currentZoomFactor, y: camera.currentZoomFactor))
        }
    }
}
#endif
