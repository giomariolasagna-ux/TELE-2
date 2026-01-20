import Foundation
import SwiftUI
import Combine
#if canImport(Photos)
import Photos
#endif

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

enum ProcessingState: Equatable {
    case idle
    case analyzingVision(progress: Double)
    case buildingPrompt(progress: Double)
    case enhancingWithAI(progress: Double)
    case completed(PlatformImage)
    case failed(reason: String, recoverable: Bool)
    
    var isProcessing: Bool {
        switch self {
        case .analyzingVision, .buildingPrompt, .enhancingWithAI:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class TeleDevelopViewModel: ObservableObject {
    @Published var state: ProcessingState = .idle
    @Published var analysis: DualAnalysisPack?
    @Published var promptBundle: PromptBundle?
    @Published var timingsMs: (vision: Int, k2: Int, openai: Int, total: Int) = (0,0,0,0)
    @Published var opticalCompression: Double = 0.0
    
    private let services: TeleServicesFactory = .make()
    private var currentTask: Task<Void, Never>?
    
    func develop(fullData: Data, cropData: Data, frame: CapturedFramePair) async {
        // Cancella task precedente
        currentTask?.cancel()
        
        let task = Task {
            let tStart = Date()
            TeleLogger.shared.log("Pipeline Started", area: "SYSTEM")
            
            // Task parallelo per preparare il crop quadrato per OpenAI mentre Moonshot lavora
            let squareCropTask = Task {
                try ImageUtils.cropForZoom(
                    fullData: fullData, 
                    zoomFactor: frame.zoomFactor, 
                    centerNorm: CGPoint(x: 0.5, y: 0.5), 
                    outputMaxDimension: 1024, 
                    forceSquare: true
                )
            }

            do {
                // Stage 1: Vision Analysis
                await updateState(.analyzingVision(progress: 0.3))
                let v0 = Date()
                let analysis: DualAnalysisPack
                analysis = try await services.vision.analyze(
                    fullImageData: fullData, 
                    cropImageData: cropData, 
                    frame: frame
                )
                let tVision = Int(Date().timeIntervalSince(v0) * 1000)
                self.analysis = analysis
                
                // Stage 2: K2 Prompt Building con validazione
                await updateState(.buildingPrompt(progress: 0.6))
                let k0 = Date()
                let prompt: PromptBundle
                prompt = try await services.k2.compilePrompt(
                    analysis: analysis, 
                    cropRect: frame.cropRectNorm, 
                    zoomFactor: frame.zoomFactor,
                    userBasePrompt: self.generateBasePrompt()
                )
                let tK2 = Int(Date().timeIntervalSince(k0) * 1000)
                self.promptBundle = prompt
                
                // Validazione K2 non bloccante
                if !self.validateAnalysisConsistency(analysis: analysis) {
                    TeleLogger.shared.log("Validazione K2 debole, procedo comunque verso OpenAI.", area: "SYSTEM")
                }
                
                // Stage 3: OpenAI Enhancement
                TeleLogger.shared.log("Stage 3: Calling OpenAI", area: "SYSTEM")
                await updateState(.enhancingWithAI(progress: 0.9))
                let o0 = Date()

                let finalData: Data
                do {
                    if let gKey = AppSecrets.geminiApiKey() {
                        TeleLogger.shared.log("Using Gemini 2.0 Flash", area: "SYSTEM")
                        let gemini = GeminiClient(apiKey: gKey)
                        let (sq, _, _, _, _, _) = try ImageUtils.cropForZoom(
                            fullData: fullData,
                            zoomFactor: frame.zoomFactor,
                            centerNorm: CGPoint(x: 0.5, y: 0.5),
                            outputMaxDimension: 1024,
                            forceSquare: true
                        )
                        _ = try await gemini.developImage(prompt: prompt.nbPrompt, imageData: sq)
                        // Fallback temporaneo per visualizzazione
                        finalData = try await services.openai.generateTelephoto(prompt: prompt, cropData: sq)
                    } else {
                        finalData = try await services.openai.generateTelephoto(prompt: prompt, cropData: cropData)
                    }
                } catch {
                    if isOverload(error) {
                        print("[TeleDevelopVM] OpenAI overloaded, using mock fallback")
                        finalData = try await MockOpenAIImagesService().generateTelephoto(
                            prompt: prompt,
                            cropData: cropData
                        )
                    } else { throw error }
                }
                guard let finalImage = PlatformImage(data: finalData) else {
                    throw NSError(domain: "OpenAI", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Dati immagine OpenAI corrotti"
                    ])
                }

                let tOpenAI = Int(Date().timeIntervalSince(o0) * 1000)
                let total = Int(Date().timeIntervalSince(tStart) * 1000)
                
                self.timingsMs = (tVision, tK2, tOpenAI, total)
                
                // Calcola Optical Compression Factor
                self.opticalCompression = self.calculateCompressionFactor(zoom: frame.zoomFactor)
                
                await updateState(.completed(finalImage))
                
            } catch {
                let errorString = String(describing: error)
                TeleLogger.shared.log("PIPELINE FATAL ERROR: \(errorString)", area: "SYSTEM")
                print("[TeleDevelopVM] Pipeline error: \(errorString)")
                await updateState(.failed(reason: errorString, recoverable: true))
            }
        }
        
        currentTask = task
        await task.value
    }
    
    private func isOverload(_ error: Error) -> Bool {
        if let te = error as? TeleError {
            switch te {
            case .serviceOverloaded: return true
            case .badServerResponse(let code): return code == 429 || code == 503
            default: return false
            }
        }
        if let urlErr = error as? URLError {
            return urlErr.code == .cannotLoadFromNetwork
        }
        return false
    }
    
    func cancel() {
        currentTask?.cancel()
        state = .idle
    }
    
    private func updateState(_ newState: ProcessingState) async {
        await MainActor.run { self.state = newState }
    }
    
    func saveToGallery(image: PlatformImage) {
        #if canImport(Photos)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                TeleLogger.shared.log("Photo Library access denied", area: "SYSTEM")
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                TeleLogger.shared.log(success ? "Saved to Gallery" : "Save Failed: \(error?.localizedDescription ?? "")", area: "SYSTEM")
            }
        }
        #else
        TeleLogger.shared.log("Photo save not supported on this platform", area: "SYSTEM")
        #endif
    }
    
    private func validateAnalysisConsistency(analysis: DualAnalysisPack) -> Bool {
        // K2: verifica che l'analisi contenga dettagli sufficienti
        guard let full = analysis.sceneSummaryFull, !full.isEmpty else { return false }
        guard let crop = analysis.sceneSummaryCrop, !crop.isEmpty else { return false }
        guard analysis.qualityFlagsCrop != nil else { return false }
        
        // Verifica che ci siano riferimenti a profondità/luci
        let depthKeywords = ["profondità", "depth", "distanza", "distance", "bokeh", "luce", "light", "ombra", "shadow"]
        let combinedText = "\(full) \(crop)".lowercased()
        
        return depthKeywords.contains { combinedText.contains($0) }
    }
    
    private func generateBasePrompt() -> String {
        """
        Enhance this photo to look as if it was captured natively with a high-quality telephoto lens.
        Preserve natural photographic grain (ISO 100 equivalent) throughout the image.
        Maintain sharp subject edges without artificial smoothing.
        """
    }
    
    private func simulateEnhancement(cropData: Data, prompt: PromptBundle) async -> PlatformImage {
        // TODO: Implementare mock visuale realistico
        // Per ora crea un'immagine di placeholder con overlay di debug
        #if canImport(UIKit)
        guard let image = UIImage(data: cropData) else {
            // Immagine di fallback
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
            return renderer.image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(origin: .zero, size: CGSize(width: 800, height: 600)))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24),
                    .foregroundColor: UIColor.white
                ]
                let text = """
                TELE Develop Preview
                \(prompt.nbPrompt)
                """
                text.draw(with: CGRect(x: 20, y: 20, width: 760, height: 560), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            }
        }
        return image
        #else
        guard let nsImage = NSImage(data: cropData) else {
            let image = NSImage(size: CGSize(width: 800, height: 600))
            image.lockFocus()
            NSColor.gray.setFill()
            __NSRectFill(NSMakeRect(0, 0, 800, 600))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.white
            ]
            let text = """
            TELE Develop Preview
            \(prompt.nbPrompt)
            """
            text.draw(in: NSMakeRect(20, 20, 760, 560), withAttributes: attrs)
            image.unlockFocus()
            return image
        }
        return nsImage
        #endif
    }
    
    private func calculateCompressionFactor(zoom: Double) -> Double {
        // Formula per calcolare fattore di compressione ottico
        // Basato su rapporto tra zoom digitale e qualità perceptita
        let baseCompression = 0.85
        let zoomCompression = min(1.0, zoom / 10.0)
        return baseCompression - (zoomCompression * 0.15)
    }
}
