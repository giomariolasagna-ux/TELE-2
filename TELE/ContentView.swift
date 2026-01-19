import SwiftUI

enum AppMode {
    case start
    case camera
}

struct ContentView: View {
    @State private var appMode: AppMode = .start
    @State private var refreshToggle: Bool = false

    var body: some View {
        Group {
            if !AppSecrets.hasAllKeys() {
                MissingApiKeyView(needsRefresh: $refreshToggle)
            } else {
                NavigationStack {
                    TeleCameraView()
                }
            }
        }
        .onAppear {
            #if DEBUG
            AppSecrets.debugDumpSources()
            #endif
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            LocalKeyDebugBadge()
        }
        #endif
    }
}

#Preview {
    ContentView()
}
#if DEBUG
private struct LocalKeyDebugBadge: View {
    private var moon: String? { AppSecrets.moonshotApiKey() }
    private var openai: String? { AppSecrets.openAIApiKey() }
    private var ok: Bool { !(moon ?? "").isEmpty && !(openai ?? "").isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color.green : Color.red).frame(width: 10, height: 10)
            Text(ok ? "Keys OK" : "Keys Missing")
                .font(.caption2).bold()
                .foregroundColor(.white)
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .padding(12)
    }
}
#endif

