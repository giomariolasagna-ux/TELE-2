import Foundation

/// Centralized secrets helper.
/// Strategy:
/// 1) Read from Process environment (ProcessInfo)
/// 2) Fallback to Info.plist (Bundle.main)
/// 3) Fallback to UserDefaults (useful for manual dev injection)
/// 4) DEBUG: print diagnostic info masked to console for quick verification
enum AppSecrets {
    private static func sanitize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var clean = trimmed.filter { !$0.isNewline && !$0.isWhitespace }
        // Rimuove punteggiatura accidentale comune nei leak/copia-incolla
        if clean.hasSuffix(".") { clean.removeLast() }
        return clean
    }

    private static func value(for name: String) -> String? {
        // 1) Process environment
        let env = ProcessInfo.processInfo.environment
        // Cerca la chiave esatta o varianti con spazi/underscore accidentali
        let target = name.replacingOccurrences(of: " ", with: "")
        for (key, val) in env {
            let cleanKey = key.replacingOccurrences(of: " ", with: "")
            if cleanKey == target && !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sanitize(val)
            }
        }

        // 2) Try common accidental variants (trailing underscore or prefix)
        let altCandidates = [name + "_", name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))]
        for alt in altCandidates {
            if let v = ProcessInfo.processInfo.environment[alt], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sanitize(v)
            }
        }

        // 3) Info.plist (useful if you added keys into Info)
        if let info = Bundle.main.object(forInfoDictionaryKey: name) as? String, !info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitize(info)
        }

        // 4) UserDefaults (manual dev injection)
        if let ud = UserDefaults.standard.string(forKey: name), !ud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitize(ud)
        }

        return nil
    }

    static func moonshotApiKey() -> String? {
        value(for: "MOONSHOT_API_KEY")
    }

    static func openAIApiKey() -> String? {
        value(for: "OPENAI_API_KEY")
    }

    static func geminiApiKey() -> String? {
        value(for: "GEMINI_API_KEY")
    }

    static func hasAllKeys() -> Bool {
        !(moonshotApiKey() ?? "").isEmpty && (!(openAIApiKey() ?? "").isEmpty || !(geminiApiKey() ?? "").isEmpty)
    }

    static func missingKeys() -> [String] {
        var missing: [String] = []
        if (moonshotApiKey() ?? "").isEmpty { missing.append("MOONSHOT_API_KEY") }
        if (openAIApiKey() ?? "").isEmpty { missing.append("OPENAI_API_KEY") }
        return missing
    }

    /// Debug helper: prints masked diagnostics to console (only in DEBUG).
    static func debugDumpSources() {
        #if DEBUG
        func mask(_ s: String?) -> String {
            guard let s = s, !s.isEmpty else { return "<empty>" }
            let suffix = s.suffix(4)
            return "••••\(suffix)"
        }

        let env = ProcessInfo.processInfo.environment
        let moonEnv = env["MOONSHOT_API_KEY"] ?? env["MOONSHOT_API_KEY_"] ?? "<not set in env>"
        let openEnv = env["OPENAI_API_KEY"] ?? env["OPENAI_API_KEY_"] ?? "<not set in env>"

        print("⟡ [AppSecrets] MOONSHOT (env) = \(mask(moonEnv))")
        print("⟡ [AppSecrets] OPENAI   (env) = \(mask(openEnv))")

        let moonPlist = Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_API_KEY") as? String
        let openPlist = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String
        print("⟡ [AppSecrets] MOONSHOT (Info.plist) = \(mask(moonPlist))")
        print("⟡ [AppSecrets] OPENAI   (Info.plist) = \(mask(openPlist))")

        let moonUD = UserDefaults.standard.string(forKey: "MOONSHOT_API_KEY")
        let openUD = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        print("⟡ [AppSecrets] MOONSHOT (UserDefaults) = \(mask(moonUD))")
        print("⟡ [AppSecrets] OPENAI   (UserDefaults) = \(mask(openUD))")
        #endif
    }
}
