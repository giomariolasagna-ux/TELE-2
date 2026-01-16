import SwiftUI

enum AppMode {
    case start
    case camera
}

struct ContentView: View {
    @State private var appMode: AppMode = .start

    var body: some View {
        Group {
            switch appMode {
            case .start:
                TeleStartView(mode: $appMode)
            case .camera:
                TeleCameraView()
            }
        }
    }
}

#Preview {
    ContentView()
}
