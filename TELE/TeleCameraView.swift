import SwiftUI
import CoreGraphics // For image size extraction

struct TeleCameraView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var developVM = TeleDevelopViewModel()
    @State private var showResult = false
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Camera Preview
            CameraPreview(camera: camera)
                .ignoresSafeArea()
            
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

        // Wait for photo capture asynchronously
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let fullData = camera.lastPhotoData,
                  let cropData = camera.lastPhotoData else {
                isProcessing = false
                return
            }

            let fullSize = extractImageSize(from: fullData)
            let cropSize = extractImageSize(from: cropData)

            let frame = CapturedFramePair(
                captureId: UUID().uuidString,
                zoomFactor: Double(camera.currentZoomFactor),
                fullWidth: fullSize.width,
                fullHeight: fullSize.height,
                cropWidth: cropSize.width,
                cropHeight: cropSize.height,
                cropRectNorm: RectNorm(x: 0.3, y: 0.3, w: 0.4, h: 0.4),
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
    
    private func extractImageSize(from data: Data) -> (width: Int, height: Int) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return (0, 0) }
        return (Int(image.size.width), Int(image.size.height))
        #else
        guard let image = NSImage(data: data) else { return (0, 0) }
        return (Int(image.size.width), Int(image.size.height))
        #endif
    }
}

// MARK: - Supporting Types
// Removed duplicate struct definitions that were causing ambiguity:
// - CapturedFramePair (now from TeleModels.swift)
// - RectNorm (now from TeleModels.swift)
// - DualAnalysisPack (now from TeleModels.swift)
// - PromptBundle (now from TeleModels.swift)

