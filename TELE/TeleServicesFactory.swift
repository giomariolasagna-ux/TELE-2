import Foundation

struct TeleServicesFactory {
    let vision: MoonshotVisionServiceProtocol
    let k2: MoonshotK2ServiceProtocol
    let openai: OpenAIImagesServiceProtocol

    static func make() -> TeleServicesFactory {
        let mKey = AppSecrets.moonshotApiKey() ?? ""
        let oKey = AppSecrets.openAIApiKey() ?? ""

        if mKey.isEmpty || oKey.isEmpty {
            return TeleServicesFactory(
                vision: MockMoonshotVisionService(),
                k2: MockMoonshotK2Service(),
                openai: MockOpenAIImagesService()
            )
        }
        
        let mClient = MoonshotClient(apiKey: mKey)
        return TeleServicesFactory(
            vision: MoonshotVisionService(client: mClient),
            k2: MoonshotK2Service(client: mClient),
            openai: OpenAIImagesClient(apiKey: oKey)
        )
    }
}
