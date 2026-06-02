import SwiftUI
import UniformTypeIdentifiers
import AudioKit

struct JSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    @EnvironmentObject private var audio: AudioManager

    @State private var isImportingSession = false
    @State private var isExportingSession = false
    @State private var isImportingSoundFont = false
    @State private var selectedImportLayer = 0
    @State private var sessionDoc: JSONDocument? = nil
    @State private var isShowingMidiMap = false
    @State private var isFullscreen = false

    static let layerColors: [Color] = [.green, .cyan, .pink, .purple]

    var body: some View {
        ZStack {
            ParticleVisualizer(bands: audio.visualizerBands, controls: audio.controls, activeScene: audio.activeScene)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                hud
                    .padding(22)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        settingsPanel
                        
                        SmartChordsView()
                        
                        ScrollingScoreView()
                        
                        instrumentLayersPanel
                        
                        if isShowingMidiMap {
                            midiMapPanel
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
        .foregroundStyle(.white)
        .onExitCommand {
            audio.panic()
        }
        .fileImporter(
            isPresented: $isImportingSoundFont,
            allowedContentTypes: [UTType(filenameExtension: "sf2")!, UTType(filenameExtension: "dls")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    audio.loadCustomInstrument(url: url, into: selectedImportLayer)
                }
            case .failure(let error):
                audio.status = "Failed to import SoundFont: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingSession,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    audio.loadSession(from: url)
                }
            case .failure(let error):
                audio.status = "Failed to load session: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $isExportingSession,
            document: sessionDoc,
            contentType: .json,
            defaultFilename: "performance_session"
        ) { result in
            switch result {
            case .success(let url):
                audio.status = "Saved session to \(url.lastPathComponent)"
            case .failure(let error):
                audio.status = "Failed to export session: \(error.localizedDescription)"
            }
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
                midiLog
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
                Text(audio.phraseStatus)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
    }

    private var settingsPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                loopGroup
                rhythmGroup
                keyGroup
                harmonyGroup
                midiGroup
                visualGroup
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    loopGroup
                    rhythmGroup
                    keyGroup
                }
                HStack(alignment: .top, spacing: 12) {
                    harmonyGroup
                    midiGroup
                    visualGroup
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private func playbackButton(title: String, isOn: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(isOn ? .black : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    isOn ? activeColor : Color.white.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? activeColor : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var loopGroup: some View {
        settingGroup("Playback") {
            HStack(spacing: 8) {
                playbackButton(title: "Loop", isOn: audio.loopEnabled, activeColor: .cyan) {
                    audio.loopEnabled.toggle()
                }
                .help("Toggle phrase looping")
                
                playbackButton(title: "Drums", isOn: audio.drumEnabled, activeColor: .pink) {
                    audio.drumEnabled.toggle()
                }
                .help("Toggle drum companion beat")
            }
        }
        .frame(width: 150)
    }

    private var rhythmGroup: some View {
        settingGroup("Rhythm") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(Int(audio.tempoBPM.rounded())) BPM")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Slider(value: $audio.tempoBPM, in: 56...168, step: 1)
                        .frame(width: 150)
                        .tint(.cyan)
                        .help("Adjust tempo (BPM)")
                }

                Picker("Time", selection: $audio.selectedTimeSignature) {
                    ForEach(TimeSignatureOption.options) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .help("Select time signature")
            }
        }
        .frame(width: 390)
    }

    private var keyGroup: some View {
        settingGroup("Key") {
            HStack(spacing: 8) {
                Picker("Root", selection: $audio.keyRootIndex) {
                    ForEach(Array(HarmonyEngine.KeySignature.pitchNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .frame(width: 76)
                .help("Select key root note")

                Picker("Scale", selection: $audio.keyMode) {
                    ForEach(HarmonyEngine.ScaleMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 118)
                .help("Select scale mode")
            }
        }
        .frame(width: 220)
    }

    private var harmonyGroup: some View {
        settingGroup("Harmony") {
            VStack(alignment: .leading, spacing: 5) {
                Text("Complexity \(Int((audio.harmonyComplexity * 100).rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Slider(value: $audio.harmonyComplexity, in: 0...1, step: 0.05)
                    .frame(width: 190)
                    .tint(.pink)
                    .help("Adjust automatic harmony complexity")
            }
        }
        .frame(width: 220)
    }

    private var midiGroup: some View {
        settingGroup("MIDI") {
            HStack(spacing: 8) {
                Stepper("Ch \(audio.padChannelNumber)", value: $audio.padChannelNumber, in: 1...16)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .help("Adjust MIDI pad channel")
                
                Button(action: {
                    isShowingMidiMap.toggle()
                }) {
                    Text("Map...")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(isShowingMidiMap ? .cyan : .white.opacity(0.12))
                .help("Toggle MIDI mappings panel")
            }
            .frame(width: 170)
        }
        .frame(width: 190)
    }

    private var visualGroup: some View {
        settingGroup("Visuals") {
            HStack(spacing: 8) {
                Picker("Scene", selection: $audio.activeScene) {
                    ForEach(VisualScene.allCases) { scene in
                        Text(scene.rawValue).tag(scene)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 105)
                .help("Select visualizer scene")
                
                Button(action: {
                    toggleFullscreen()
                }) {
                    Image(systemName: isFullscreen ? "arrows.semibold.compress" : "arrows.semibold.expand")
                        .font(.body.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.12))
                .help("Toggle Fullscreen")
            }
            .frame(width: 145)
        }
        .frame(width: 165)
    }

    private func toggleFullscreen() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isFullscreen = window.styleMask.contains(.fullScreen)
            }
        }
    }

    private func settingGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
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

    private var midiLog: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(audio.midiEvents.prefix(3)) { event in
                Text(event.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }
        }
        .padding(.top, 3)
    }

    private var instrumentLayersPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("INSTRUMENTS")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                sessionControls
            }
            .padding(.horizontal, 10)
            
            VStack(spacing: 6) {
                ForEach(0..<4) { index in
                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(audio.currentLayer == index ? ContentView.layerColors[index % 4] : Color.white.opacity(0.2))
                                .frame(width: 8, height: 8)
                            
                            Text("Layer \(index + 1)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(audio.currentLayer == index ? .white : .white.opacity(0.6))
                        }
                        .frame(width: 76, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            audio.selectLayer(index)
                        }
                        
                        Spacer()
                        
                        instrumentMenu(for: index)
                            .frame(width: 240, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(audio.currentLayer == index ? ContentView.layerColors[index % 4].opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(audio.currentLayer == index ? ContentView.layerColors[index % 4].opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var sessionControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                isImportingSession = true
            }) {
                Label("Load Session", systemImage: "square.and.arrow.down")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.12))
            .help("Import saved performance session JSON")
            
            Button(action: {
                let state = audio.getSessionState()
                if let data = try? JSONEncoder().encode(state) {
                    sessionDoc = JSONDocument(data: data)
                    isExportingSession = true
                }
            }) {
                Label("Save Session", systemImage: "square.and.arrow.up")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.12))
            .help("Export current performance session to JSON")
        }
    }

    private func instrumentMenu(for index: Int) -> some View {
        Menu {
            Section("Starter Presets") {
                ForEach(InstrumentPreset.starterPresets) { preset in
                    Button(action: { audio.loadPreset(preset, into: index) }) {
                        Text(preset.name)
                    }
                }
            }
            
            if !audio.importedSoundFonts.isEmpty {
                Section("Imported Library") {
                    ForEach(audio.importedSoundFonts) { sf in
                        Button(action: {
                            audio.loadCustomInstrument(bookmarkData: sf.bookmarkData, into: index, filename: sf.name)
                        }) {
                            HStack {
                                Text(sf.name)
                                Image(systemName: "doc.music")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Button(action: {
                selectedImportLayer = index
                isImportingSoundFont = true
            }) {
                Label("Import SoundFont / DLS...", systemImage: "doc.badge.plus")
            }
        } label: {
            HStack {
                Text(audio.layers[index].name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white)
        }
    }

    private var midiMapPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MIDI MAPPINGS")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
                
                Spacer()
                
                Text(audio.connectedDevices.isEmpty ? "No MIDI inputs" : "Inputs: \(audio.connectedDevices.joined(separator: ", "))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.trailing, 10)
                
                Button(action: {
                    audio.mappingConfig = MIDIMappingConfiguration.default
                    audio.saveMappingConfig()
                    audio.activeLearnSlot = nil
                    audio.status = "Reset MIDI mappings to default."
                }) {
                    Text("Reset Defaults")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.6))
            }
            .padding(.horizontal, 10)

            HStack(alignment: .top, spacing: 20) {
                // Knobs Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("KNOBS (CC)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, 4)
                    
                    ForEach(ControlTarget.allCases) { target in
                        HStack {
                            Text(target.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 140, alignment: .leading)
                            
                            Spacer()
                            
                            let ccVal = audio.mappingConfig.ccMappings.first(where: { $0.value == target })?.key
                            
                            Button(action: {
                                if audio.activeLearnSlot == .cc(target) {
                                    audio.activeLearnSlot = nil
                                } else {
                                    audio.activeLearnSlot = .cc(target)
                                    audio.status = "Learn: Move a knob on your MIDI controller..."
                                }
                            }) {
                                if audio.activeLearnSlot == .cc(target) {
                                    Text("Waiting...")
                                        .font(.caption.bold().monospaced())
                                        .frame(width: 90, height: 22)
                                        .background(Color.cyan)
                                        .foregroundStyle(.black)
                                        .cornerRadius(4)
                                } else {
                                    Text(ccVal != nil ? "CC \(ccVal!)" : "Unmapped")
                                        .font(.caption.monospaced())
                                        .frame(width: 90, height: 22)
                                        .background(.white.opacity(0.08))
                                        .foregroundStyle(.white.opacity(ccVal != nil ? 1.0 : 0.4))
                                        .cornerRadius(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(.white.opacity(0.12), lineWidth: 1)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .frame(width: 280)
                
                // Divider
                Color.white.opacity(0.1)
                    .frame(width: 1)
                    .padding(.vertical, 4)
                
                // Pads Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("PADS (NOTE LEARN)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, 4)
                    
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                    
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(0..<16) { index in
                            let noteVal = audio.mappingConfig.padMappings.first(where: { $0.value == index })?.key
                            let isLearning = audio.activeLearnSlot == .pad(index)
                            
                            Button(action: {
                                if isLearning {
                                    audio.activeLearnSlot = nil
                                } else {
                                    audio.activeLearnSlot = .pad(index)
                                    audio.status = "Learn: Press a pad on your MIDI controller..."
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Text("Pad \(index + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isLearning ? "LEARN" : (noteVal != nil ? "N \(noteVal!)" : "---"))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(isLearning ? .black : .white.opacity(noteVal != nil ? 0.8 : 0.3))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(isLearning ? Color.cyan : (noteVal != nil ? .white.opacity(0.08) : .white.opacity(0.03)))
                                .foregroundStyle(isLearning ? .black : .white)
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isLearning ? Color.cyan : .white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

}

private struct DiatonicChordPad: Identifiable {
    let id: Int
    let romanNumeral: String
    let displayName: String
    let rootNote: MIDINoteNumber
}

struct SmartChordsView: View {
    @EnvironmentObject private var audio: AudioManager
    @State private var activePadID: Int?
    @State private var highlightGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CHORD PADS")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.leading, 10)

            ViewThatFits(in: .horizontal) {
                chordStrip
                ScrollView(.horizontal, showsIndicators: false) {
                    chordStrip
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var chordStrip: some View {
        HStack(spacing: 8) {
            ForEach(chordPads) { pad in
                Button {
                    triggerChord(pad)
                } label: {
                    VStack(spacing: 4) {
                        Text(pad.romanNumeral)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text(pad.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 96)
                    .foregroundStyle(activePadID == pad.id ? .black : .white)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activePadID == pad.id ? Color.cyan : Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(activePadID == pad.id ? Color.cyan.opacity(0.95) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(activePadID == pad.id ? 0.32 : 0.18), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .scaleEffect(activePadID == pad.id ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: activePadID)
                .accessibilityLabel(pad.displayName)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var chordPads: [DiatonicChordPad] {
        let tonic = 60 + audio.keyRootIndex
        let scale = scaleIntervals(for: audio.keyMode)

        return (0..<8).map { index in
            let scaleIndex = index % scale.count
            let octave = index / scale.count
            let root = clampMIDINote(tonic + scale[scaleIndex] + octave * 12)
            return DiatonicChordPad(
                id: index,
                romanNumeral: romanNumeral(for: index, mode: audio.keyMode),
                displayName: displayName(for: root, degree: index, mode: audio.keyMode),
                rootNote: root
            )
        }
    }

    private func triggerChord(_ pad: DiatonicChordPad) {
        activePadID = pad.id
        highlightGeneration += 1
        let generation = highlightGeneration

        audio.triggerQuantizedOneShotNote(pad.rootNote, velocity: 100, channel: 1, quantizeToGrid: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard highlightGeneration == generation, activePadID == pad.id else { return }
            activePadID = nil
        }
    }

    private func scaleIntervals(for mode: HarmonyEngine.ScaleMode) -> [Int] {
        switch mode {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11]
        case .minor:
            return [0, 2, 3, 5, 7, 8, 10]
        case .pentatonic:
            return [0, 2, 4, 7, 9]
        }
    }

    private func romanNumeral(for degree: Int, mode: HarmonyEngine.ScaleMode) -> String {
        switch mode {
        case .major:
            return ["I", "ii", "iii", "IV", "V", "vi", "vii°", "I"][degree]
        case .minor:
            return ["i", "ii°", "III", "iv", "v", "VI", "VII", "i"][degree]
        case .pentatonic:
            return ["I", "II", "III", "V", "VI", "I", "II", "III"][degree]
        }
    }

    private func displayName(for note: MIDINoteNumber, degree: Int, mode: HarmonyEngine.ScaleMode) -> String {
        let pitchNames = HarmonyEngine.KeySignature.pitchNames
        let rootName = pitchNames[Int(note % 12)]

        switch mode {
        case .major:
            return "\(rootName) \(["Maj", "min", "min", "Maj", "Maj", "min", "dim", "Maj"][degree])"
        case .minor:
            return "\(rootName) \(["min", "dim", "Maj", "min", "min", "Maj", "Maj", "min"][degree])"
        case .pentatonic:
            return rootName
        }
    }

    private func clampMIDINote(_ value: Int) -> MIDINoteNumber {
        MIDINoteNumber(max(0, min(127, value)))
    }
}
