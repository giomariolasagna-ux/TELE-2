import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MissingApiKeyView: View {
    @Binding var needsRefresh: Bool
    @State private var showEntrySheet: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Missing API Key")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Set MOONSHOT_API_KEY in Xcode → Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    // Simple refresh by toggling the binding
                    needsRefresh.toggle()
                } label: {
                    Text("I've set it")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Open instructions") {
                            NotificationCenter.default.post(name: .teleShowKeyHelp, object: nil)
                        }
                        .buttonStyle(.bordered)

                        Button("Enter keys (dev)") {
                            showEntrySheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 8)
                .sheet(isPresented: $showEntrySheet) {
                    DevKeyEntryView()
                }
            }
        }
    }
}

#Preview {
    MissingApiKeyView(needsRefresh: .constant(false))
}
struct DevKeyEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var moonKey: String = ""
    @State private var openAIKey: String = ""
    @State private var showSavedAlert: Bool = false

    var body: some View {
        NavigationView {
            Form {
                #if canImport(UIKit)
                HStack {
                    SecureField("Moonshot Key", text: $moonKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") { moonKey = UIPasteboard.general.string ?? "" }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                HStack {
                    SecureField("OpenAI Key", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") { openAIKey = UIPasteboard.general.string ?? "" }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                #endif

                Section(header: Text("Moonshot API Key")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $moonKey)
                            .frame(minHeight: 44, maxHeight: 120)
                            .font(.system(.body, design: .monospaced))
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
#endif
#if os(iOS)
                        Button("Paste from Clipboard") {
                            if let s = UIPasteboard.general.string { moonKey = s }
                        }
                        .buttonStyle(.bordered)
#endif
                    }
                }
                Section(header: Text("OpenAI API Key")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $openAIKey)
                            .frame(minHeight: 44, maxHeight: 120)
                            .font(.system(.body, design: .monospaced))
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
#endif
#if os(iOS)
                        Button("Paste from Clipboard") {
                            if let s = UIPasteboard.general.string { openAIKey = s }
                        }
                        .buttonStyle(.bordered)
#endif
                    }
                }
                Section {
                    VStack(spacing: 8) {
                        Button("Save keys to UserDefaults (dev only)") { save() }
                            .buttonStyle(.borderedProminent)
                        Button(role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: "MOONSHOT_API_KEY")
                            UserDefaults.standard.removeObject(forKey: "OPENAI_API_KEY")
                            moonKey = ""
                            openAIKey = ""
                            AppSecrets.debugDumpSources()
                        } label: {
                            Text("Clear saved keys (dev)")
                        }
                    }
                }
            }
            .navigationTitle("Enter API Keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if let m = UserDefaults.standard.string(forKey: "MOONSHOT_API_KEY") { moonKey = m }
                if let o = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") { openAIKey = o }
            }
            .alert("Saved", isPresented: $showSavedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Keys saved. Re-run the app from Xcode (Cmd+R) for full reliability.")
            }
        }
    }

    private func save() {
        let m = moonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { UserDefaults.standard.set(m, forKey: "MOONSHOT_API_KEY") }
        if !o.isEmpty { UserDefaults.standard.set(o, forKey: "OPENAI_API_KEY") }
        AppSecrets.debugDumpSources()
        showSavedAlert = true
    }
}

extension Notification.Name {
    static let teleShowKeyHelp = Notification.Name("tele.showKeyHelp")
}
