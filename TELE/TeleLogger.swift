import Foundation
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !os(iOS)
import AppKit
#endif

/// Singleton per la raccolta di eventi diagnostici da fornire rapidamente all'IA.
final class TeleLogger: ObservableObject {
    static let shared = TeleLogger()
    @Published var logs: [String] = []
    private let maxEntries = 100
    
    func log(_ message: String, area: String = "SYSTEM") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] [\(area)] \(message)"
        
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxEntries { self.logs.removeFirst() }
            print(entry)
        }
    }
    
    func exportForAI() -> String {
        #if canImport(UIKit)
        let deviceLine = "Device: \(UIDevice.current.model) | iOS: \(UIDevice.current.systemVersion)"
        #elseif canImport(AppKit)
        let deviceLine = "Device: macOS | Version: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        let deviceLine = "Device: unknown"
        #endif
        
        let header = """
        ### TELE DIAGNOSTIC REPORT ###
        \(deviceLine)
        Date: \(Date())
        -------------------------------------------
        """
        return header + "\n" + logs.joined(separator: "\n")
    }
    
    func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = exportForAI()
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportForAI(), forType: .string)
        #endif
    }
}

struct DebugLogOverlay: View {
    @ObservedObject var logger = TeleLogger.shared
    
    var body: some View {
        Button(action: { logger.copyToClipboard() }) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                Text("Copy Logs for AI")
            }
            .font(.caption2.bold())
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
        }
    }
}
