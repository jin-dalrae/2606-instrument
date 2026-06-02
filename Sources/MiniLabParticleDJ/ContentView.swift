import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var audio: AudioManager

    var body: some View {
        ZStack {
            ParticleVisualizer(bands: audio.visualizerBands, controls: audio.controls)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                hud
                    .padding(22)
                Spacer()
                instrumentPadPreview
                    .padding(18)
            }
        }
        .foregroundStyle(.white)
        .onExitCommand {
            audio.panic()
        }
    }

    private var hud: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(activeLayer.name)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(audio.lastMIDIEvent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(audio.scaleLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(audio.status)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
    }

    private var instrumentPadPreview: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 42, maximum: 78), spacing: 8), count: 8),
            spacing: 8
        ) {
            ForEach(InstrumentPreset.starterPresets) { preset in
                VStack(spacing: 4) {
                    Text("\(preset.id + 1)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(preset.name)
                        .font(.system(size: 10, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(padFill(for: preset), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(activeLayer.preset.id == preset.id ? 0.38 : 0.10), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: 680)
        .opacity(0.78)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
    }

    private var activeLayer: LayerState {
        guard audio.layers.indices.contains(audio.currentLayer) else {
            return audio.layers[0]
        }
        return audio.layers[audio.currentLayer]
    }

    private func padFill(for preset: InstrumentPreset) -> Color {
        if activeLayer.preset.id == preset.id {
            return Color(red: 0.12, green: 0.58, blue: 0.92).opacity(0.72)
        }

        if audio.lastPadIndex == preset.id {
            return Color(red: 0.92, green: 0.28, blue: 0.46).opacity(0.62)
        }

        return .black.opacity(0.24)
    }
}
