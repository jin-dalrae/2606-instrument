import SwiftUI

@main
struct MiniLabParticleDJApp: App {
    @StateObject private var audio = AudioManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    audio.start()
                }
                .onDisappear {
                    audio.stop()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                audio.stop()
            }
        }
    }
}
