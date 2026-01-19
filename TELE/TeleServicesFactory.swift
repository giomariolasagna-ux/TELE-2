import Foundation

struct TeleServicesFactory {
    let vision: MoonshotVisionServiceProtocol
    let k2: MoonshotK2ServiceProtocol

    static func make() -> TeleServicesFactory {
        guard let key = AppSecrets.moonshotApiKey(), !key.isEmpty else {
            return TeleServicesFactory(vision: MockMoonshotVisionService(), k2: MockMoonshotK2Service())
        }
        let client = MoonshotClient(apiKey: key)
        let vision = MoonshotVisionService(client: client)
        let k2 = MoonshotK2Service(client: client)
        return TeleServicesFactory(vision: vision, k2: k2)
    }
}
