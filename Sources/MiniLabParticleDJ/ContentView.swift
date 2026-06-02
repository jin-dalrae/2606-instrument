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
                rhythmPanel
                    .padding(20)
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
                Text("\(audio.scaleLabel)  \(audio.chordLabel)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(audio.harmonyLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Text(audio.status)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
    }

    private var rhythmPanel: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $audio.loopEnabled) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Speed")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(Int(audio.tempoBPM.rounded())) BPM")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }

                Slider(value: $audio.tempoBPM, in: 56...168, step: 1)
                    .frame(width: 220)
                    .tint(.cyan)
            }

            Picker("Rhythm", selection: $audio.loopBeats) {
                Text("2 beat").tag(2.0)
                Text("4 beat").tag(4.0)
                Text("8 beat").tag(8.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var activeLayer: LayerState {
        guard audio.layers.indices.contains(audio.currentLayer) else {
            return audio.layers[0]
        }
        return audio.layers[audio.currentLayer]
    }

}
