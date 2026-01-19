import Foundation

protocol OpenAIImagesServiceProtocol {
    func generateTelephoto(prompt: PromptBundle, cropData: Data) async throws -> Data
}

final class OpenAIImagesClient: OpenAIImagesServiceProtocol {
    private let apiKey: String
    private let urlSession: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1/images/edits")!
    
    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }
    
    func generateTelephoto(prompt: PromptBundle, cropData: Data) async throws -> Data {
        let b64Image = "data:image/png;base64,\(cropData.base64EncodedString())"
        let payload: [String: Any] = [
            "model": "gpt-image-1.5",
            "image": b64Image,
            "prompt": prompt.nbPrompt,
            "n": 1,
            "size": "1024x1024",
            "response_format": "b64_json"
        ]
        
        var req = URLRequest(url: baseURL, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        var attempt = 0
        var lastError: Error?
        
        while attempt < 3 {
            do {
                let (data, resp) = try await urlSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                
                if (200..<300).contains(http.statusCode) {
                    let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    if let b64 = decoded.data.first?.b64_json, let imageData = Data(base64Encoded: b64) {
                        return imageData
                    }
                    throw URLError(.cannotDecodeContentData)
                } else if [429, 503].contains(http.statusCode) {
                    attempt += 1
                    if attempt >= 3 { throw URLError(.cannotLoadFromNetwork) }
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                } else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                lastError = error
                attempt += 1
                if attempt >= 3 { break }
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }
        throw lastError ?? URLError(.unknown)
    }
    
    private struct OpenAIResponse: Codable {
        struct ImageResult: Codable {
            var b64_json: String?
            var url: String?
        }
        var data: [ImageResult]
    }
}

final class MockOpenAIImagesService: OpenAIImagesServiceProtocol {
    func generateTelephoto(prompt: PromptBundle, cropData: Data) async throws -> Data {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return cropData // Fallback to original crop in mock
    }
}
