import SwiftUI

struct TeleStartView: View {
    @Binding var mode: AppMode

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Logo Tipografico
                Text("TELE")
                    .font(.system(size: 64, weight: .black, design: .default))
                    .tracking(-3)
                    .foregroundStyle(.white)
                
                Text("Pure Optical Interface")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                    .tracking(2)
                
                Spacer()
                
                // Bottone di avvio
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        mode = .camera
                    }
                } label: {
                    Text("OPEN LENS")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.white)
                        .cornerRadius(40)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    TeleStartView(mode: .constant(.start))
}
