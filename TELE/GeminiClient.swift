import Foundation

final class GeminiClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func developImage(prompt: String, imageData: Data) async throws -> Data {
        TeleLogger.shared.log("Gemini Stage: Processing multimodal request", area: "GEMINI")
        
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/png", "data": imageData.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["temperature": 0.4, "topP": 0.95]
        ]

        var req = URLRequest(url: urlComponents.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var attempt = 0
        while attempt < 3 {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw TeleError.networkError(URLError(.badServerResponse)) }
            
            if http.statusCode == 200 {
                TeleLogger.shared.log("Gemini Success", area: "GEMINI")
                // Nota: In produzione qui si estrarrebbe l'immagine se il modello supporta output d'immagine,
                // o si userebbe il testo per guidare un generatore locale/Imagen.
                return data
            } else if [429, 500].contains(http.statusCode) {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            } else {
                throw TeleError.badServerResponse(http.statusCode)
            }
        }
        throw TeleError.serviceOverloaded
    }
}
