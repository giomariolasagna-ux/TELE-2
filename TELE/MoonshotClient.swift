import Foundation

struct ChatMessage: Codable {
    var role: String
    var content: [MessageContent]

    enum MessageContent: Codable {
        case text(String)
        case image(url: String)
        
        enum CodingKeys: String, CodingKey { 
            case type, text, image_url 
        }
        
        struct ImageURL: Codable { 
            var url: String 
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let t):
                try container.encode("text", forKey: .type)
                try container.encode(t, forKey: .text)
            case .image(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURL(url: url), forKey: .image_url)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            if type == "text" {
                let text = try container.decode(String.self, forKey: .text)
                self = .text(text)
            } else if type == "image_url" {
                let imageData = try container.decode(ImageURL.self, forKey: .image_url)
                self = .image(url: imageData.url)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type")
            }
        }
    }
    
    // Helper init per backward compatibility
    init(role: String, text: String) {
        self.role = role
        self.content = [.text(text)]
    }
    
    // Init for content array (needed for messages with images)
    init(role: String, content: [MessageContent]) {
        self.role = role
        self.content = content
    }
}

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var role: String
            var content: String
        }
        var index: Int
        var message: Message
        var finish_reason: String?
    }
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [Choice]
}

final class MoonshotClient {
    private let baseURL = URL(string: "https://api.moonshot.ai/v1")!
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func chatCompletions(model: String, messages: [ChatMessage], temperature: Double? = nil, maxTokens: Int? = nil) async throws -> ChatCompletionResponse {
        TeleLogger.shared.log("Requesting completion for model: \(model)", area: "MOONSHOT")
        let payload: [String: Any] = {
            let processedMessages = messages.map { msg -> [String: Any] in
                // Se il contenuto è solo testo, lo appiattiamo a Stringa per massima compatibilità
                if msg.content.count == 1, case .text(let t) = msg.content.first {
                    return ["role": msg.role, "content": t]
                }
                
                // Altrimenti usiamo l'array (multimodale)
                let contentArray = msg.content.map { content -> [String: Any] in
                    switch content {
                    case .text(let text):
                        return ["type": "text", "text": text]
                    case .image(let url):
                        return ["type": "image_url", "image_url": ["url": url]]
                    }
                }
                return ["role": msg.role, "content": contentArray]
            }

            var dict: [String: Any] = [
                "model": model,
                "messages": processedMessages
            ]
            if let temperature { dict["temperature"] = temperature }
            if let maxTokens { dict["max_tokens"] = maxTokens }
            return dict
        }()

        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url, timeoutInterval: 120) // Aumentato per immagini
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        TeleLogger.shared.log("Auth Header present: \(!apiKey.isEmpty)", area: "MOONSHOT")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            do {
                let (data, resp) = try await urlSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw TeleError.badServerResponse(-1) }

                if (200..<300).contains(http.statusCode) {
                    do {
                        TeleLogger.shared.log("HTTP \(http.statusCode) Success", area: "MOONSHOT")
                        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                    } catch {
                        let body = String(data: data, encoding: .utf8) ?? "no body"
                        TeleLogger.shared.log("JSON Decode failed: \(error). Body: \(body.prefix(300))", area: "MOONSHOT")
                        throw TeleError.decodingFailed
                    }
                } else if [429, 503].contains(http.statusCode) {
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After") ?? "1"
                    let waitSeconds = Double(retryAfter) ?? pow(2.0, Double(attempt))
                    TeleLogger.shared.log("HTTP \(http.statusCode) Rate Limit. Wait \(waitSeconds)s.", area: "MOONSHOT")
                    if attempt == 2 { throw TeleError.serviceOverloaded }
                    let delay = UInt64(waitSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    attempt += 1
                    continue
                } else {
                    if let body = String(data: data, encoding: .utf8) {
                        TeleLogger.shared.log("HTTP \(http.statusCode) body=\(body)", area: "MOONSHOT")
                    }
                    throw TeleError.badServerResponse(http.statusCode)
                }
            } catch {
                if let te = error as? TeleError, case .serviceOverloaded = te { throw te }
                lastError = error
                attempt += 1
                if attempt < 3 {
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw TeleError.networkError(lastError ?? URLError(.unknown))
    }
}
