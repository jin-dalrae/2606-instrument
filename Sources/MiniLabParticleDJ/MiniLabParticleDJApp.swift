import SwiftUI

@main
struct MiniLabParticleDJApp: App {
    @StateObject private var audio = AudioManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    audio.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
