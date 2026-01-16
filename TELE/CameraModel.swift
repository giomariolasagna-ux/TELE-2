import SwiftUI
import AVFoundation
import Combine // INDISPENSABILE per correggere l'errore "does not conform to ObservableObject"
import UIKit   // INDISPENSABILE per correggere gli errori su UIView

class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var isSessionRunning = false

    // Coda dedicata per la sessione AVFoundation
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // Gestione Zoom
    var device: AVCaptureDevice?
    @Published var currentZoomFactor: CGFloat = 1.0

    // Output foto per validare la pipeline
    private let photoOutput = AVCapturePhotoOutput()

    // Throttle per lo zoom: evita lock/unlock eccessivi durante gesture
    private var lastZoomUpdateTime: CFTimeInterval = 0
    private let zoomUpdateInterval: CFTimeInterval = 1.0 / 30.0 // max 30 Hz

    override init() {
        super.init()
        checkPermissions()
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
            do {
                self.session.beginConfiguration()

                // Preset bilanciato per preview fluida (puoi cambiare in .high o .photo se necessario)
                if self.session.canSetSessionPreset(.high) {
                    self.session.sessionPreset = .high
                }

                // Input: preferisci back, altrimenti front
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                    print("[Camera] Nessun device video disponibile")
                    self.session.commitConfiguration()
                    return
                }
                self.device = device

                // Configurazione del device: priorità continuità messa a fuoco/esposizione per preview stabile
                do {
                    try device.lockForConfiguration()
                    if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                    if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
                    device.unlockForConfiguration()
                } catch {
                    print("[Camera] Impossibile configurare il device: \(error)")
                }

                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    print("[Camera] Input aggiunto")
                } else {
                    print("[Camera] Impossibile aggiungere input")
                }

                // Output foto (mantieni disabilitata livellazione se non serve)
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    if #available(iOS 16.0, *) {
                        // Usa la massima dimensione supportata per miglior qualità
                        if let maxDim = self.photoOutput.__availablePhotoDimensions()?.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                            self.photoOutput.maxPhotoDimensions = maxDim
                        }
                    } else {
                        self.photoOutput.isHighResolutionCaptureEnabled = true
                    }
                    print("[Camera] PhotoOutput aggiunto")
                } else {
                    print("[Camera] Impossibile aggiungere PhotoOutput")
                }

                self.session.commitConfiguration()
                print("[Camera] Commit configuration")

                if !self.session.isRunning {
                    self.session.startRunning()
                    print("[Camera] Sessione avviata")
                }

                DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
            } catch {
                print("[Camera] Errore setup camera: \(error)")
            }
        }
    }
    
    func setZoom(factor: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastZoomUpdateTime >= zoomUpdateInterval else { return }
        lastZoomUpdateTime = now

        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
                let newZoom = max(1.0, min(factor, maxZoom))
                if abs(device.videoZoomFactor - newZoom) > 0.001 {
                    device.ramp(toVideoZoomFactor: newZoom, withRate: 8.0) // ramp veloce ma fluida
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.currentZoomFactor = newZoom }
            } catch {
                print("[Camera] Zoom error: \(error)")
            }
        }
    }

    // MARK: - Lifecycle helpers
    func startSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = true }
            }
        }
    }

    func stopSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isSessionRunning = false }
            }
        }
    }
}

// Wrapper per SwiftUI
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = .resizeAspectFill
        
        if let device = camera.device {
            if #available(iOS 17.0, *) {
                let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                context.coordinator.rotationCoordinator = rc
                let angle = rc.videoRotationAngleForHorizonLevelCapture
                if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            } else {
                if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                    let orientation = legacyVideoOrientation(from: view)
                    connection.videoOrientation = orientation
                }
            }
        }
        
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = context.coordinator.previewLayer {
            if layer.frame != uiView.bounds { layer.frame = uiView.bounds }
            if let connection = layer.connection {
                if #available(iOS 17.0, *) {
                    if let rc = context.coordinator.rotationCoordinator {
                        let angle = rc.videoRotationAngleForHorizonLevelCapture
                        if connection.isVideoRotationAngleSupported(angle) && connection.videoRotationAngle != angle {
                            connection.videoRotationAngle = angle
                        }
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        let newOrientation = legacyVideoOrientation(from: uiView)
                        if connection.videoOrientation != newOrientation {
                            connection.videoOrientation = newOrientation
                        }
                    }
                }
            }
        }
    }
    
    private func legacyVideoOrientation(from view: UIView) -> AVCaptureVideoOrientation /* deprecated pre-iOS17, used for fallback */ {
        if #available(iOS 26.0, *) {
            let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
            switch orientation {
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            case .portraitUpsideDown: return .portraitUpsideDown
            default: return .portrait
            }
        } else {
            let orientation = view.window?.windowScene?.interfaceOrientation
            switch orientation {
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            case .portraitUpsideDown: return .portraitUpsideDown
            default: return .portrait
            }
        }
    }
}
