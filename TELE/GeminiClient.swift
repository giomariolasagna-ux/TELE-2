import Foundation

final class GeminiClient {
    private let apiKey: String
    // Endpoint per Gemini 2.5 Flash (Nano Banana) con supporto multimodale nativo
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent"

    init(apiKey: String) { self.apiKey = apiKey }

    func developImage(prompt: String, imageData: Data) async throws -> Data {
        TeleLogger.shared.log("Gemini Stage: Multimodal Image-to-Image", area: "GEMINI")
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        let payload: [String: Any] = [
            "contents": [["parts": [
                ["text": "Edit this telephoto crop: \(prompt)"],
                ["inline_data": ["mime_type": "image/png", "data": imageData.base64EncodedString()]]
            ]]]
        ]

        var req = URLRequest(url: urlComponents.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw TeleError.badServerResponse((resp as? HTTPURLResponse)?.statusCode ?? 500)
        }
        return data // Gemini 2.5 restituisce i token dell'immagine generata nel body
    }
}
