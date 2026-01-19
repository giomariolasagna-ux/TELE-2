import Foundation

protocol MoonshotVisionServiceProtocol {
    func analyze(fullImageData: Data, cropImageData: Data, frame: CapturedFramePair) async throws -> DualAnalysisPack
}

final class MoonshotVisionService: MoonshotVisionServiceProtocol {
    private let client: MoonshotClient
    private let modelName: String = "moonshot-v1-8k-vision-preview"
    
    init(client: MoonshotClient) {
        self.client = client
    }
    
    func analyze(fullImageData: Data, cropImageData: Data, frame: CapturedFramePair) async throws -> DualAnalysisPack {
        let fullB64 = fullImageData.base64EncodedString()
        let cropB64 = cropImageData.base64EncodedString()
        
        // Build messages with images using explicit enum qualification
        let systemMsg = ChatMessage(
            role: "system", 
            content: [
                ChatMessage.MessageContent.text("Sei un esperto di ottiche teleobiettivo. Analizza le due immagini: la prima è il contesto Full Frame, la seconda è il dettaglio Croppato. Descrivi luci, colori e profondità di campo. Rispondi SOLO in JSON.")
            ]
        )
        
        let userMsg = ChatMessage(
            role: "user", 
            content: [
                ChatMessage.MessageContent.text("Analizza contesto (Full) e dettaglio (Crop). Zoom: \(frame.zoomFactor)x."),
                ChatMessage.MessageContent.image(url: "data:image/jpeg;base64,\(fullB64)"),
                ChatMessage.MessageContent.image(url: "data:image/jpeg;base64,\(cropB64)")
            ]
        )
        
        let response = try await client.chatCompletions(
            model: modelName,
            messages: [systemMsg, userMsg],
            temperature: 0.2,
            maxTokens: 1000
        )
        
        let content = response.choices.first?.message.content ?? "{}"
        
        // Validate JSON
        guard let jsonData = Self.extractFirstJSONObject(from: content) else {
            throw NSError(domain: "VisionValidation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Vision ha generato output non-JSON: \(content.prefix(100))"
            ])
        }
        
        do {
            var pack = try JSONDecoder().decode(DualAnalysisPack.self, from: jsonData)
            pack.captureId = frame.captureId
            return pack
        } catch {
            print("[VisionService] Decode fallito, content=\(content.prefix(200))")
            throw error
        }
    }
    
    private static func extractFirstJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1; if depth == 0 { return Data(text[start...idx].utf8) } }
            idx = text.index(after: idx)
        }
        return nil
    }
}

final class MockMoonshotVisionService: MoonshotVisionServiceProtocol {
    func analyze(fullImageData: Data, cropImageData: Data, frame: CapturedFramePair) async throws -> DualAnalysisPack {
        try? await Task.sleep(nanoseconds: 800_000_000)
        return DualAnalysisPack(
            captureId: frame.captureId,
            sceneSummaryFull: "Mock full scene analysis with telephoto constraints",
            sceneSummaryCrop: "Mock crop analysis showing subject isolation",
            qualityFlagsCrop: "sharp, well-exposed, minor noise",
            constraints: "preserve grain, natural bokeh, avoid oversmoothing"
        )
    }
}
