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
                settingsPanel
                    .padding(.horizontal, 22)
                Spacer()
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
                playedLog
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(audio.scaleLabel)  \(audio.chordLabel)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("\(audio.harmonyLabel)  \(audio.selectedTimeSignature.label)")
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

    private var settingsPanel: some View {
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
                    .frame(width: 170)
                    .tint(.cyan)
            }

            Picker("Time", selection: $audio.selectedTimeSignature) {
                ForEach(TimeSignatureOption.options) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)

            Picker("Key", selection: $audio.keyRootIndex) {
                ForEach(Array(HarmonyEngine.KeySignature.pitchNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .frame(width: 78)

            Picker("Scale", selection: $audio.keyMode) {
                ForEach(HarmonyEngine.ScaleMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .frame(width: 112)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Complex")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(Int((audio.harmonyComplexity * 100).rounded()))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }

                Slider(value: $audio.harmonyComplexity, in: 0...1, step: 0.05)
                    .frame(width: 150)
                    .tint(.pink)
            }

            Toggle(isOn: $audio.drumEnabled) {
                Label("Drums", systemImage: "metronome")
            }
            .toggleStyle(.button)

            Stepper("Pad Ch \(audio.padChannelNumber)", value: $audio.padChannelNumber, in: 1...16)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 110)
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

    private var playedLog: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(audio.playedEvents.prefix(5)) { event in
                Text("\(event.noteName)  \(event.instrumentName)  \(event.harmonyName)  \(event.rhythmName)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }

}
