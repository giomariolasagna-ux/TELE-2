import Foundation

struct TeleServicesFactory {
    let vision: MoonshotVisionServiceProtocol
    let k2: MoonshotK2ServiceProtocol
    let openai: OpenAIImagesServiceProtocol
    let gemini: GeminiClient?

    static func make() -> TeleServicesFactory {
        let mKey = AppSecrets.moonshotApiKey() ?? ""
        let oKey = AppSecrets.openAIApiKey() ?? ""
        let gKey = AppSecrets.geminiApiKey()

        // Vision/K2 depend on Moonshot key; fallback to mocks if missing
        let mClient = mKey.isEmpty ? nil : MoonshotClient(apiKey: mKey)
        let visionService: MoonshotVisionServiceProtocol = mClient != nil ? MoonshotVisionService(client: mClient!) : MockMoonshotVisionService()
        let k2Service: MoonshotK2ServiceProtocol = mClient != nil ? MoonshotK2Service(client: mClient!) : MockMoonshotK2Service()

        // OpenAI optional; fallback to mock if missing
        let openaiService: OpenAIImagesServiceProtocol = oKey.isEmpty ? MockOpenAIImagesService() : OpenAIImagesClient(apiKey: oKey)

        let geminiClient: GeminiClient? = gKey.map { GeminiClient(apiKey: $0) }

        return TeleServicesFactory(
            vision: visionService,
            k2: k2Service,
            openai: openaiService,
            gemini: geminiClient
        )
    }
}
