import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        TeleLogger.shared.log("Starting OpenAI Image Generation (DALL-E 2 Edit)", area: "OPENAI")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var body = Data()
        let params: [String: String] = [
            "model": "dall-e-2",
            "prompt": prompt.nbPrompt,
            "n": "1",
            "size": "1024x1024",
            "response_format": "b64_json"
        ]
        
        for (key, value) in params {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // OpenAI richiede PNG per l'upload di immagini
        let pngData: Data
        #if canImport(UIKit)
        if let image = UIImage(data: cropData), let converted = image.pngData() {
            pngData = converted
        } else {
            pngData = cropData
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: cropData),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let converted = rep.representation(using: .png, properties: [:]) {
            pngData = converted
        } else {
            pngData = cropData
        }
        #else
        pngData = cropData
        #endif
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"crop.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(pngData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = body
        TeleLogger.shared.log("Multipart payload prepared (Size: \(body.count) bytes)", area: "OPENAI")
        
        var attempt = 0
        var lastError: Error?
        
        while attempt < 3 {
            do {
                let (data, resp) = try await urlSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                
                if (200..<300).contains(http.statusCode) {
                    TeleLogger.shared.log("HTTP \(http.statusCode) Success", area: "OPENAI")
                    let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    if let b64 = decoded.data.first?.b64_json, let imageData = Data(base64Encoded: b64) {
                        return imageData
                    }
                    throw URLError(.cannotDecodeContentData)
                } else if [429, 503].contains(http.statusCode) {
                    TeleLogger.shared.log("HTTP \(http.statusCode) Rate Limit. Retrying...", area: "OPENAI")
                    attempt += 1
                    if attempt >= 3 { throw URLError(.cannotLoadFromNetwork) }
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                } else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "no body"
                    TeleLogger.shared.log("HTTP \(http.statusCode) Error: \(errorBody)", area: "OPENAI")
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
