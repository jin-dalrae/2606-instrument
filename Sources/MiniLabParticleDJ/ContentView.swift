import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var audio: AudioManager
    @State private var isImportingInstrument = false

    private let soundFontType = UTType(filenameExtension: "sf2") ?? .data
    private let dlsType = UTType(filenameExtension: "dls") ?? .data

    var body: some View {
        ZStack {
            ParticleVisualizer(bands: audio.visualizerBands, controls: audio.controls)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                performanceSurface
            }
            .padding(22)
        }
        .fileImporter(
            isPresented: $isImportingInstrument,
            allowedContentTypes: [soundFontType, dlsType],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                audio.loadCustomInstrument(url: url, into: audio.currentLayer)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MiniLab Particle DJ")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(audio.status)  \(audio.lastMIDIEvent)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.70))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(audio.scaleLabel)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Auto harmony")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .foregroundStyle(.white)
    }

    private var performanceSurface: some View {
        HStack(alignment: .bottom, spacing: 18) {
            layersPanel
            padsPanel
            controlsPanel
        }
        .padding(18)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layers")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(audio.layers) { layer in
                Button {
                    audio.selectLayer(layer.id)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(layer.id + 1)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(width: 28, height: 28)
                            .background(layer.id == audio.currentLayer ? .white : .white.opacity(0.12), in: Circle())
                            .foregroundStyle(layer.id == audio.currentLayer ? .black : .white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(layer.isLoaded ? "ready" : "loading")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        Spacer()
                    }
                    .padding(10)
                    .frame(width: 230)
                    .background(layer.id == audio.currentLayer ? .white.opacity(0.18) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button {
                isImportingInstrument = true
            } label: {
                Label("Load SF2", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var padsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pads")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("36-51")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.58))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(86), spacing: 10), count: 8), spacing: 10) {
                ForEach(InstrumentPreset.starterPresets) { preset in
                    Button {
                        audio.loadPreset(preset, into: audio.currentLayer)
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(preset.id + 1)")
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(.white.opacity(0.65))
                            Text(preset.name)
                                .font(.system(size: 11, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                        }
                        .frame(width: 86, height: 66)
                        .background(padFill(for: preset), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 728)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Knobs")
                .font(.headline)
                .foregroundStyle(.white)

            ControlSlider(title: "Brightness", value: $audio.controls.brightness, color: .cyan)
            ControlSlider(title: "Gravity", value: $audio.controls.gravity, color: .green)
            ControlSlider(title: "Size", value: $audio.controls.particleSize, color: .pink)
            ControlSlider(title: "Trail", value: $audio.controls.trail, color: .orange)

            Divider()
                .overlay(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 8) {
                MeterRow(title: "Bass", value: audio.visualizerBands.bass, color: .cyan)
                MeterRow(title: "Mid", value: audio.visualizerBands.mid, color: .green)
                MeterRow(title: "High", value: audio.visualizerBands.treble, color: .pink)
            }
        }
        .frame(width: 210)
    }

    private func padFill(for preset: InstrumentPreset) -> Color {
        if audio.layers[audio.currentLayer].preset.id == preset.id {
            return Color(red: 0.18, green: 0.58, blue: 0.92).opacity(0.86)
        }

        if audio.lastPadIndex == preset.id {
            return Color(red: 0.92, green: 0.28, blue: 0.46).opacity(0.70)
        }

        return .white.opacity(0.08)
    }
}

private struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 127))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.62))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)

            Slider(value: $value, in: 0...1)
                .tint(color)
        }
    }
}

private struct MeterRow: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 42, alignment: .leading)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.82))
                            .frame(width: proxy.size.width * value.clamped(to: 0...1))
                    }
            }
            .frame(height: 8)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
