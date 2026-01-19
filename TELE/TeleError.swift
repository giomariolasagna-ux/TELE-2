import Foundation

enum TeleError: Error, CustomStringConvertible {
    case serviceOverloaded
    case badServerResponse(Int)
    case decodingFailed
    case networkError(Error)
    case visionAnalysisFailed(String)
    case promptGenerationFailed(String)

    var description: String {
        switch self {
        case .serviceOverloaded: return "Servizio sovraccarico (429/503). Riprova tra poco."
        case .badServerResponse(let code): return "Errore server HTTP \(code)."
        case .decodingFailed: return "Errore decodifica dati AI."
        case .networkError(let e): return "Errore di rete: \(e.localizedDescription)"
        case .visionAnalysisFailed(let msg): return "Analisi Vision fallita: \(msg)"
        case .promptGenerationFailed(let msg): return "Generazione Prompt fallita: \(msg)"
        }
    }
}
