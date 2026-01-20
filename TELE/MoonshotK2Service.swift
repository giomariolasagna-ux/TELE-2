import Foundation

protocol MoonshotK2ServiceProtocol {
    func compilePrompt(analysis: DualAnalysisPack, cropRect: RectNorm, zoomFactor: Double, userBasePrompt: String) async throws -> PromptBundle
}

final class MoonshotK2Service: MoonshotK2ServiceProtocol {
    private let client: MoonshotClient
    private let modelName: String = "moonshot-v1-8k" // Cambio modello per velocità istantanea

    init(client: MoonshotClient) { self.client = client }

    func compilePrompt(analysis: DualAnalysisPack, cropRect: RectNorm, zoomFactor: Double, userBasePrompt: String) async throws -> PromptBundle {
        let system = ChatMessage(
            role: "system", 
            text: """
                Sei un prompt engineer specializzato in fotografia teleobiettivo.
                Analizza i dati forniti e crea un prompt per DALL-E 3 che:
                1. Specifichi correzione aberrazioni e distorsioni
                2. Richieda bokeh naturale con profondità corretta
                3. Mantenga grana fotografica uniforme (ISO 100)
                4. Eviti smoothing artificiale su aree lisce (cielo)
                5. Validi coerenza tra analisi full e crop
                
                Rispondi SOLO con JSON valido usando snake_case per le chiavi: 
                "nb_prompt", "nb_negative", "render_notes".
                """
        )
        
        let user = ChatMessage(
            role: "user", 
            text: """
                Analisi Vision: \(analysis)
                Crop Rect: \(cropRect)
                Zoom Factor: \(zoomFactor)
                User Prompt: \(userBasePrompt)
                
                Genera prompt ottimale per telephoto simulation.
                """
        )
        
        let resp = try await client.chatCompletions(model: modelName, messages: [system, user], temperature: 0.3, maxTokens: 1000)
        let content = resp.choices.first?.message.content ?? "{}"
        
        // K2 Validation Layer: verifica JSON prima di restituire
        guard let jsonData = Self.extractFirstJSONObject(from: content) else {
            throw TeleError.promptGenerationFailed("Output non-JSON: \(content.prefix(100))")
        }
        
        do {
            var bundle = try JSONDecoder().decode(PromptBundle.self, from: jsonData)
            bundle.captureId = analysis.captureId // Iniettiamo l'ID originale per sicurezza
            return bundle
        } catch {
            print("[K2Service] Decode fallito, content=\(content.prefix(200))")
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

final class MockMoonshotK2Service: MoonshotK2ServiceProtocol {
    func compilePrompt(analysis: DualAnalysisPack, cropRect: RectNorm, zoomFactor: Double, userBasePrompt: String) async throws -> PromptBundle {
        try? await Task.sleep(nanoseconds: 500_000_000)
        return PromptBundle(
            captureId: analysis.captureId ?? UUID().uuidString,
            nbPrompt: "\(userBasePrompt) | Zoom: \(zoomFactor)x | Crop: \(cropRect)",
            nbNegative: "blurry, distorted, artificial, over-smoothed, fake bokeh",
            renderNotes: "Mock K2 processing with grain preservation"
        )
    }
}
