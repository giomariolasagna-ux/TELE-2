import SwiftUI

struct TeleCameraView: View {
    @StateObject var camera = CameraModel() // Il nostro motore Camera
    @State private var showGrid: Bool = true
    
    // Gestione stato Zoom gesto
    @State private var baseZoom: CGFloat = 1.0
    @GestureState private var gestureZoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // --- TOP BAR ---
                HStack {
                    Button { showGrid.toggle() } label: {
                        Image(systemName: showGrid ? "grid" : "rectangle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    // Indicatore Zoom/Esposizione
                    HStack(spacing: 4) {
                        Text("ZOOM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1fx", camera.currentZoomFactor)) // Mostra lo zoom reale
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .frame(height: 60)
                
                Spacer()
                
                // --- MIRINO (VIEWFINDER 4:3) ---
                ZStack {
                    // 1. VIDEO REALE (Sostituisce il rettangolo grigio)
                    CameraPreview(camera: camera)
                        .clipShape(RoundedRectangle(cornerRadius: 12)) // Taglia gli angoli
                        .aspectRatio(3/4, contentMode: .fit)
                    
                    // 2. GRIGLIA
                    if showGrid {
                        ZStack {
                            HStack { Spacer(); Divider().background(.white.opacity(0.3)); Spacer(); Divider().background(.white.opacity(0.3)); Spacer() }
                            VStack { Spacer(); Divider().background(.white.opacity(0.3)); Spacer(); Divider().background(.white.opacity(0.3)); Spacer() }
                        }
                        .aspectRatio(3/4, contentMode: .fit)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 8)
                // --- GESTURE ZOOM (Trackpad o Dita) ---
                .gesture(
                    MagnificationGesture()
                        .updating($gestureZoomScale) { value, state, _ in
                            state = value
                            // Anteprima live dello zoom mentre muovi le dita
                            let newZoom = baseZoom * value
                            DispatchQueue.main.async {
                                camera.setZoom(factor: newZoom)
                            }
                        }
                        .onEnded { value in
                            // Salva lo zoom finale quando stacchi le dita
                            baseZoom *= value
                            // Correzione limiti per evitare valori assurdi
                            if baseZoom < 1.0 { baseZoom = 1.0 }
                            if baseZoom > 5.0 { baseZoom = 5.0 }
                        }
                )
                
                Spacer()
                
                // --- BOTTOM BAR ---
                HStack(alignment: .center) {
                    // Galleria
                    Button {} label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.2))
                            .frame(width: 50, height: 50)
                            .overlay(Image(systemName: "photo").foregroundStyle(.white))
                    }
                    
                    Spacer()
                    
                    // Tasto Scatto
                    Button {} label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                            Circle().fill(.white).frame(width: 70, height: 70)
                        }
                    }
                    
                    Spacer()
                    
                    // Reset Zoom (Tasto rapido)
                    Button {
                        baseZoom = 1.0
                        camera.setZoom(factor: 1.0)
                    } label: {
                        Circle()
                            .fill(Color(white: 0.2))
                            .frame(width: 50, height: 50)
                            .overlay(Text("1x").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .frame(height: 120)
            }
        }
        .onAppear {
            camera.checkPermissions()
        }
    }
}

