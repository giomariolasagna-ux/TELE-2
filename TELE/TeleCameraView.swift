import SwiftUI
import CoreGraphics // For CGPoint math

struct TeleCameraView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var developVM = TeleDevelopViewModel()
    @State private var showResult = false
    @State private var isProcessing = false
    @State private var pinchScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Camera Preview
            CameraPreview(camera: camera)
                .ignoresSafeArea()
                .simultaneousGesture(zoomGesture)
            
            VStack {
                Spacer()
                
                // Processing indicator
                if developVM.state.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                        .padding()
                }
                
                // Capture Button
                Button {
                    captureAndProcess()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.8), lineWidth: 4)
                                .frame(width: 70, height: 70)
                        }
                }
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.5 : 1)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            camera.checkPermissions()
        }
        .sheet(isPresented: $showResult) {
            VStack(spacing: 16) {
                Text("Result")
                    .font(.title)
                    .bold()
                if case let .completed(result) = developVM.state {
                    Text("Development completed")
                        .font(.headline)
                    // You can render result here when ready
                } else if developVM.state.isProcessing {
                    ProgressView()
                } else {
                    Text("No result available")
                }
                Button("Close") { showResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    @MainActor private func captureAndProcess() {
        isProcessing = true
        camera.capturePhoto()

        Task { @MainActor in
            // Polling leggero per attendere lo scatto
            var data: Data? = nil
            for _ in 0..<15 {
                if let d = camera.lastPhotoData { data = d; break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            guard let fullData = data else { isProcessing = false; return }

            // Calcolo crop deterministico 10x centrato
            let zoom = CGFloat(camera.currentZoomFactor)
            let cropResult = try? ImageUtils.cropForZoom(
                fullData: fullData,
                zoomFactor: zoom,
                centerNorm: CGPoint(x: 0.5, y: 0.5)
            )
            
            guard let (cropData, cropRect, fW, fH, cW, cH) = cropResult else {
                isProcessing = false; return 
            }

            let frame = CapturedFramePair(
                captureId: UUID().uuidString,
                zoomFactor: Double(zoom),
                fullWidth: fW, fullHeight: fH,
                cropWidth: cW, cropHeight: cH,
                cropRectNorm: RectNorm(x: Double(cropRect.minX), y: Double(cropRect.minY), w: Double(cropRect.width), h: Double(cropRect.height)),
                metadata: CameraMetadata(
                    iso: Double(camera.currentISO),
                    shutterS: camera.currentExposureDuration,
                    ev: Double(camera.currentExposureBias),
                    wbKelvin: 5500,
                    focalMm: nil,
                    orientationUpright: true
                )
            )

            await developVM.develop(
                fullData: fullData,
                cropData: cropData,
                frame: frame
            )

            if case .completed = developVM.state {
                showResult = true
            }
            isProcessing = false
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / pinchScale
                pinchScale = value
                let newZoom = camera.currentZoomFactor * delta
                camera.setZoom(factor: newZoom)
            }
            .onEnded { _ in
                pinchScale = 1.0
            }
    }
}

// MARK: - Supporting Types
// Removed duplicate struct definitions that were causing ambiguity:
// - CapturedFramePair (now from TeleModels.swift)
// - RectNorm (now from TeleModels.swift)
// - DualAnalysisPack (now from TeleModels.swift)
// - PromptBundle (now from TeleModels.swift)
