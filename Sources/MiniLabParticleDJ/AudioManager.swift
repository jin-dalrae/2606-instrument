@preconcurrency import AudioKit
import AVFoundation
import Combine
import CoreMIDI
import Foundation

struct LayerState: Identifiable {
    let id: Int
    var name: String
    var preset: InstrumentPreset
    var isLoaded: Bool = false
    var activeNotes: Set<MIDINoteNumber> = []
    var volume: Double = 1.0
    var isMuted: Bool = false
    var isSoloed: Bool = false
    var octaveOffset: Int = 0
    var delayFeedback: Double = 0.3
    var delayTime: Double = 0.35
    var delayDryWet: Double = 0.0
    var reverbDryWet: Double = 0.0
}

struct VisualizerBands {
    var amplitude: Double = 0
    var bass: Double = 0
    var mid: Double = 0
    var treble: Double = 0
    var lastVelocity: Double = 0
    var triggerID: Int = 0
}

struct PerformanceControls {
    var brightness: Double = 0.76
    var gravity: Double = 0.42
    var particleSize: Double = 0.54
    var trail: Double = 0.68
}

struct PlayedEvent: Identifiable {
    let id = UUID()
    let noteName: String
    let instrumentName: String
    let harmonyName: String
    let rhythmName: String
}

struct MIDIEventLog: Identifiable {
    let id = UUID()
    let label: String
}

private struct PerformanceVoice {
    let layer: Int
    let instrumentID: Int
    let note: MIDINoteNumber
    let channel: MIDIChannel
    let velocityRatio: Double
}

private struct StartedPerformanceNote {
    let token: UUID
    let startedAt: Date
    let startOffset: TimeInterval
    let sourceVelocity: MIDIVelocity
    let instrumentName: String
    let harmonyName: String
    let rhythmName: String
    let voices: [PerformanceVoice]
}

private struct CapturedPhraseNote {
    let startOffset: TimeInterval
    let duration: TimeInterval
    let sourceVelocity: MIDIVelocity
    let voices: [PerformanceVoice]
}

@MainActor
final class AudioManager: ObservableObject {
    let padBaseNote: MIDINoteNumber = 36
    
    var connectedDevices: [String] {
        midi.inputNames
    }

    @Published var currentLayer = 0
    @Published var layers: [LayerState]
    @Published var importedSoundFonts: [ImportedSoundFont] = []
    @Published var activeLearnSlot: LearnSlot? = nil
    @Published var mappingConfig = MIDIMappingConfiguration.default
    @Published var visualizerBands = VisualizerBands()
    @Published var controls = PerformanceControls()
    @Published var activeScene: VisualScene = .hyperdrive
    @Published var tempoBPM: Double = 96
    @Published var selectedTimeSignature = TimeSignatureOption.options[0]
    @Published var loopEnabled = true
    @Published var drumEnabled = true
    @Published var harmonyComplexity: Double = 0.45
    @Published var keyRootIndex = 0
    @Published var keyMode = HarmonyEngine.ScaleMode.major
    @Published var padChannelNumber = 10
    @Published var scaleLabel = "C Major"
    @Published var chordLabel = "No Chord"
    @Published var harmonyLabel = "Close 3rds"
    @Published var status = "Audio engine idle"
    @Published var lastMIDIEvent = "Waiting for MiniLab Mk2"
    @Published var lastPadIndex: Int?
    @Published var playedEvents: [PlayedEvent] = []
    @Published var phraseStatus = "Phrase empty"
    @Published var midiEvents: [MIDIEventLog] = []
    @Published var scoreNotes: [ScoreNote] = []
    @Published var visualsEnabled = false
    @Published var scoreEnabled = false

    private let engine = AudioEngine()
    private let mixer = Mixer()
    private let midi = MIDI()
    private let harmony = HarmonyEngine()
    private var samplers: [AppleSampler] = []
    private var delays: [Delay] = []
    private var reverbs: [Reverb] = []
    private var loopSamplers: [AppleSampler] = []
    private let drumSampler = AppleSampler()
    private var fftTap: FFTTap?
    private var loadedCustomInstrumentURLs: [Int: URL] = [:]
    private var loadedCustomInstrumentBookmarks: [Int: Data] = [:]
    private var voicesBySourceNote: [MIDINoteNumber: [PerformanceVoice]] = [:]
    private var startedNotes: [MIDINoteNumber: StartedPerformanceNote] = [:]
    private var activePadNotes: Set<MIDINoteNumber> = []
    private var recentMelodyNotes: [MIDINoteNumber] = []
    private var harmonySettings = HarmonySettings()
    private var loopGeneration = 0
    private var drumGeneration = 0
    private var currentPreset = InstrumentPreset.starterPresets[0]
    private var measureAnchor = Date()
    private var phraseNotes: [CapturedPhraseNote] = []
    private var phraseMeasureIndex = 0
    private var phraseScheduleGeneration = 0
    private var hasStarted = false
    private var oneShotGeneration = 0
    private var activeOneShotNote: (note: MIDINoteNumber, channel: MIDIChannel)?

    private var padChannel: MIDIChannel {
        MIDIChannel(max(0, min(15, padChannelNumber - 1)))
    }

    init() {
        Settings.bufferLength = .short
        Settings.recordingBufferLength = .short

        let presets = InstrumentPreset.starterPresets
        let starterPreset = presets[0]
        layers = (0..<4).map { index in
            LayerState(id: index, name: "Layer \(index + 1)", preset: starterPreset)
        }

        for _ in 0..<4 {
            let sampler = AppleSampler()
            samplers.append(sampler)
            
            let delay = Delay(sampler)
            delay.time = 0.35
            delay.feedback = 0.3
            delay.dryWetMix = 0.0
            delays.append(delay)
            
            let reverb = Reverb(delay)
            reverb.dryWetMix = 0.0
            reverbs.append(reverb)
            
            mixer.addInput(reverb)
        }

        for _ in InstrumentPreset.starterPresets {
            let sampler = AppleSampler()
            loopSamplers.append(sampler)
            mixer.addInput(sampler)
        }

        mixer.addInput(drumSampler)
        engine.output = mixer
        midi.addListener(self)
        loadImportedSoundFonts()
        loadMappingConfig()
    }

    func start() {
        guard !hasStarted else { return }
        do {
            try engine.start()
            hasStarted = true
            measureAnchor = Date()
            openMIDIInputs()
            if visualsEnabled {
                configureFFT()
            }
            loadLoopPresets()
            loadDrums()
            
            if let autoURL = autoSaveURL, FileManager.default.fileExists(atPath: autoURL.path) {
                autoRestoreSession()
            } else {
                loadStarterPresets()
            }
            
            startDrumLoop()
            publishMIDIInputStatus()
        } catch {
            publishStatus("Engine failed: \(error.localizedDescription)")
        }
    }

    /// (Re)connect to every Core MIDI source. AudioKit only enumerates inputs at
    /// the moment `openInput()` is called, so a controller that appears late or is
    /// hot-plugged is invisible until we open again. Close first so re-opening an
    /// already-connected device doesn't leak its port.
    func openMIDIInputs() {
        midi.closeAllInputs()
        midi.openInput()
        logMIDI("inputs: \(connectedDevices.isEmpty ? "none" : connectedDevices.joined(separator: ", "))")
    }

    private func publishMIDIInputStatus() {
        if connectedDevices.isEmpty {
            publishStatus("Engine running. No MIDI inputs detected — connect your MiniLab.")
        } else {
            publishStatus("Engine running. Listening to: \(connectedDevices.joined(separator: ", ")).")
        }
    }

    func stop() {
        autoSaveSession()
        panic()
        drumGeneration += 1
        fftTap?.stop()
        midi.closeAllInputs()
        engine.stop()
        hasStarted = false
        publishStatus("Engine stopped.")
    }

    func panic() {
        for sampler in samplers + loopSamplers + [drumSampler] {
            for note in MIDINoteNumber(0)...MIDINoteNumber(127) {
                for channel in MIDIChannel(0)...MIDIChannel(15) {
                    sampler.stop(noteNumber: note, channel: channel)
                }
            }
        }

        loopGeneration += 1
        phraseScheduleGeneration += 1
        oneShotGeneration += 1
        activeOneShotNote = nil
        phraseNotes.removeAll()
        voicesBySourceNote.removeAll()
        startedNotes.removeAll()
        recentMelodyNotes.removeAll()
        for layer in self.layers.indices {
            self.layers[layer].activeNotes.removeAll()
        }
        if scoreEnabled {
            for idx in scoreNotes.indices {
                if scoreNotes[idx].endTime == nil {
                    scoreNotes[idx].endTime = Date()
                }
            }
        }
        self.phraseStatus = "Phrase empty"
        self.lastMIDIEvent = "All notes off"
    }

    func selectLayer(_ layer: Int) {
        guard layers.indices.contains(layer) else { return }
        currentLayer = layer
    }

    func triggerQuantizedOneShotNote(
        _ note: MIDINoteNumber,
        velocity: MIDIVelocity = 100,
        channel: MIDIChannel = 1,
        quantizeToGrid: Bool = true
    ) {
        oneShotGeneration += 1
        let generation = oneShotGeneration

        if let activeOneShotNote {
            noteOff(activeOneShotNote.note, channel: activeOneShotNote.channel)
            self.activeOneShotNote = nil
        }

        let startDelay = quantizeToGrid ? delayToNextGridBoundary(from: Date()) : 0
        let holdDuration = oneShotHoldDuration()

        Task { @MainActor in
            if startDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
            }

            guard self.oneShotGeneration == generation else { return }

            self.noteOn(note, velocity: velocity, channel: channel)
            self.activeOneShotNote = (note, channel)

            if holdDuration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            }

            guard self.oneShotGeneration == generation else { return }
            guard self.activeOneShotNote?.note == note, self.activeOneShotNote?.channel == channel else { return }

            self.noteOff(note, channel: channel)
            self.activeOneShotNote = nil
        }
    }

    func triggerChordPadNote(
        _ note: MIDINoteNumber,
        velocity: MIDIVelocity = 100,
        channel: MIDIChannel = 1
    ) {
        triggerQuantizedOneShotNote(note, velocity: velocity, channel: channel, quantizeToGrid: false)
    }

    func setLayerVolume(layer: Int, volume: Double) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].volume = volume
        updateSamplerVolumes()
    }

    func setLayerMuted(layer: Int, isMuted: Bool) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].isMuted = isMuted
        updateSamplerVolumes()
    }

    func setLayerSoloed(layer: Int, isSoloed: Bool) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].isSoloed = isSoloed
        updateSamplerVolumes()
    }

    func setLayerOctave(layer: Int, octaveOffset: Int) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].octaveOffset = octaveOffset
    }

    func shouldSilenceLayer(_ layer: Int) -> Bool {
        guard layers.indices.contains(layer) else { return false }
        let hasSolo = layers.contains(where: \.isSoloed)
        if hasSolo {
            return !layers[layer].isSoloed
        } else {
            return layers[layer].isMuted
        }
    }

    func updateSamplerVolumes() {
        let hasSolo = layers.contains(where: \.isSoloed)
        for i in 0..<samplers.count {
            guard layers.indices.contains(i) else { continue }
            let isMuted = layers[i].isMuted
            let isSoloed = layers[i].isSoloed
            let targetVolume: Double
            if hasSolo {
                targetVolume = isSoloed ? layers[i].volume : 0.0
            } else {
                targetVolume = isMuted ? 0.0 : layers[i].volume
            }
            samplers[i].volume = AUValue(targetVolume)
        }
    }

    func updateFXSettings(for layer: Int) {
        guard layers.indices.contains(layer),
              delays.indices.contains(layer),
              reverbs.indices.contains(layer) else { return }
        
        let state = layers[layer]
        delays[layer].feedback = AUValue(state.delayFeedback)
        delays[layer].time = AUValue(state.delayTime)
        delays[layer].dryWetMix = AUValue(state.delayDryWet * 100)
        reverbs[layer].dryWetMix = AUValue(state.reverbDryWet * 100)
    }

    func setLayerDelayFeedback(layer: Int, feedback: Double) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].delayFeedback = feedback
        updateFXSettings(for: layer)
    }
    
    func setLayerDelayTime(layer: Int, time: Double) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].delayTime = time
        updateFXSettings(for: layer)
    }
    
    func setLayerDelayDryWet(layer: Int, dryWet: Double) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].delayDryWet = dryWet
        updateFXSettings(for: layer)
    }
    
    func setLayerReverbDryWet(layer: Int, dryWet: Double) {
        guard layers.indices.contains(layer) else { return }
        layers[layer].reverbDryWet = dryWet
        updateFXSettings(for: layer)
    }

    func loadCustomInstrument(url: URL, into layer: Int) {
        guard samplers.indices.contains(layer) else { return }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try samplers[layer].loadInstrument(url: url)
            loadedCustomInstrumentURLs[layer] = url
            
            // Create security scoped bookmark
            var bookmarkData: Data? = nil
            do {
                bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                print("Failed to create bookmark: \(error)")
            }
            if let bookmarkData {
                loadedCustomInstrumentBookmarks[layer] = bookmarkData
                addImportedSoundFont(url: url, bookmarkData: bookmarkData)
            } else {
                loadedCustomInstrumentBookmarks.removeValue(forKey: layer)
            }
            
            self.layers[layer].name = url.deletingPathExtension().lastPathComponent
            self.layers[layer].isLoaded = true
            self.publishStatus("Loaded \(url.lastPathComponent) into layer \(layer + 1).")
        } catch {
            publishStatus("Could not load \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func loadCustomInstrument(bookmarkData: Data, into layer: Int, filename: String) {
        guard samplers.indices.contains(layer) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            try samplers[layer].loadInstrument(url: url)
            loadedCustomInstrumentURLs[layer] = url
            loadedCustomInstrumentBookmarks[layer] = bookmarkData
            
            self.layers[layer].name = filename
            self.layers[layer].isLoaded = true
            self.publishStatus("Loaded \(filename) into layer \(layer + 1).")
        } catch {
            publishStatus("Could not resolve bookmark for layer \(layer + 1): \(error.localizedDescription)")
        }
    }

    func loadPreset(_ preset: InstrumentPreset, into layer: Int) {
        guard samplers.indices.contains(layer) else { return }

        do {
            try samplers[layer].samplerUnit.loadSoundBankInstrument(
                at: StarterSoundBank.systemDLSURL,
                program: preset.program,
                bankMSB: preset.bankMSB,
                bankLSB: preset.bankLSB
            )

            self.loadedCustomInstrumentURLs[layer] = nil
            self.layers[layer].preset = preset
            self.layers[layer].name = preset.name
            self.layers[layer].isLoaded = true
            self.publishStatus("Layer \(layer + 1): \(preset.name)")
        } catch {
            publishStatus("Could not load \(preset.name): \(error.localizedDescription)")
        }
    }

    func getSessionState() -> SessionState {
        let tsIndex = TimeSignatureOption.options.firstIndex(of: selectedTimeSignature) ?? 0
        let pLayers = layers.map { layer in
            let customBookmark = loadedCustomInstrumentBookmarks[layer.id]
            let customFilename = loadedCustomInstrumentURLs[layer.id]?.lastPathComponent
            let presetID = customBookmark == nil ? layer.preset.id : nil
            return PersistableLayerState(
                id: layer.id,
                name: layer.name,
                presetID: presetID,
                customInstrumentBookmarkData: customBookmark,
                customInstrumentFilename: customFilename,
                volume: layer.volume,
                isMuted: layer.isMuted,
                isSoloed: layer.isSoloed,
                octaveOffset: layer.octaveOffset,
                delayFeedback: layer.delayFeedback,
                delayTime: layer.delayTime,
                delayDryWet: layer.delayDryWet,
                reverbDryWet: layer.reverbDryWet
            )
        }
        return SessionState(
            tempoBPM: tempoBPM,
            selectedTimeSignatureIndex: tsIndex,
            loopEnabled: loopEnabled,
            drumEnabled: drumEnabled,
            harmonyComplexity: harmonyComplexity,
            keyRootIndex: keyRootIndex,
            keyModeRawValue: keyMode.rawValue,
            padChannelNumber: padChannelNumber,
            currentLayer: currentLayer,
            activeScene: activeScene,
            layers: pLayers
        )
    }

    func applySessionState(_ state: SessionState) {
        self.tempoBPM = state.tempoBPM
        if TimeSignatureOption.options.indices.contains(state.selectedTimeSignatureIndex) {
            self.selectedTimeSignature = TimeSignatureOption.options[state.selectedTimeSignatureIndex]
        }
        self.loopEnabled = state.loopEnabled
        self.drumEnabled = state.drumEnabled
        self.harmonyComplexity = state.harmonyComplexity
        self.keyRootIndex = state.keyRootIndex
        if let mode = HarmonyEngine.ScaleMode(rawValue: state.keyModeRawValue) {
            self.keyMode = mode
        }
        self.padChannelNumber = state.padChannelNumber
        self.currentLayer = state.currentLayer
        self.activeScene = state.activeScene ?? .hyperdrive
        
        for pLayer in state.layers {
            let layerId = pLayer.id
            guard self.layers.indices.contains(layerId) else { continue }
            self.layers[layerId].volume = pLayer.volume
            self.layers[layerId].isMuted = pLayer.isMuted
            self.layers[layerId].isSoloed = pLayer.isSoloed
            self.layers[layerId].octaveOffset = pLayer.octaveOffset
            self.layers[layerId].delayFeedback = pLayer.delayFeedback ?? 0.3
            self.layers[layerId].delayTime = pLayer.delayTime ?? 0.35
            self.layers[layerId].delayDryWet = pLayer.delayDryWet ?? 0.0
            self.layers[layerId].reverbDryWet = pLayer.reverbDryWet ?? 0.0
            
            if let bookmarkData = pLayer.customInstrumentBookmarkData,
               let filename = pLayer.customInstrumentFilename {
                self.loadCustomInstrument(bookmarkData: bookmarkData, into: layerId, filename: filename)
            } else if let presetId = pLayer.presetID,
                      let preset = InstrumentPreset.starterPresets.first(where: { $0.id == presetId }) {
                self.loadPreset(preset, into: layerId)
            }
            
            self.updateFXSettings(for: layerId)
        }
        
        self.updateSamplerVolumes()
        self.publishStatus("Session loaded successfully.")
    }

    func saveSession(to url: URL) {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let state = getSessionState()
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            try data.write(to: url)
            publishStatus("Session saved to \(url.lastPathComponent)")
        } catch {
            publishStatus("Failed to save session: \(error.localizedDescription)")
        }
    }

    func loadSession(from url: URL) {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let state = try decoder.decode(SessionState.self, from: data)
            applySessionState(state)
        } catch {
            publishStatus("Failed to load session: \(error.localizedDescription)")
        }
    }

    private var autoSaveURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("MiniLabParticleDJ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("last_session.json")
    }

    func autoSaveSession() {
        guard let url = autoSaveURL else { return }
        do {
            let state = getSessionState()
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            try data.write(to: url)
        } catch {
            print("Auto-save failed: \(error)")
        }
    }

    func autoRestoreSession() {
        guard let url = autoSaveURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let state = try decoder.decode(SessionState.self, from: data)
            applySessionState(state)
            publishStatus("Last session automatically restored.")
        } catch {
            print("Auto-restore failed: \(error)")
        }
    }

    func addImportedSoundFont(url: URL, bookmarkData: Data) {
        let name = url.deletingPathExtension().lastPathComponent
        if !importedSoundFonts.contains(where: { $0.name == name }) {
            self.importedSoundFonts.append(ImportedSoundFont(name: name, bookmarkData: bookmarkData))
            self.saveImportedSoundFonts()
        }
    }

    private func saveImportedSoundFonts() {
        if let data = try? JSONEncoder().encode(importedSoundFonts) {
            UserDefaults.standard.set(data, forKey: "imported_soundfonts")
        }
    }

    private func loadImportedSoundFonts() {
        if let data = UserDefaults.standard.data(forKey: "imported_soundfonts"),
           let list = try? JSONDecoder().decode([ImportedSoundFont].self, from: data) {
            self.importedSoundFonts = list
        }
    }

    func saveMappingConfig() {
        if let data = try? JSONEncoder().encode(mappingConfig) {
            UserDefaults.standard.set(data, forKey: "midi_mapping_config")
        }
    }

    func loadMappingConfig() {
        if let data = UserDefaults.standard.data(forKey: "midi_mapping_config"),
           let config = try? JSONDecoder().decode(MIDIMappingConfiguration.self, from: data) {
            self.mappingConfig = config
        }
    }

    private func loadStarterPresets() {
        for layer in layers.indices {
            loadPreset(layers[layer].preset, into: layer)
        }
    }

    private func loadLoopPresets() {
        for preset in InstrumentPreset.starterPresets where loopSamplers.indices.contains(preset.id) {
            do {
                try loopSamplers[preset.id].samplerUnit.loadSoundBankInstrument(
                    at: StarterSoundBank.systemDLSURL,
                    program: preset.program,
                    bankMSB: preset.bankMSB,
                    bankLSB: preset.bankLSB
                )
            } catch {
                publishStatus("Could not load loop \(preset.name): \(error.localizedDescription)")
            }
        }
    }

    private func loadDrums() {
        do {
            try drumSampler.samplerUnit.loadSoundBankInstrument(
                at: StarterSoundBank.systemDLSURL,
                program: 0,
                bankMSB: 0x78,
                bankLSB: 0
            )
        } catch {
            publishStatus("Could not load drum kit: \(error.localizedDescription)")
        }
    }

    private func loadPerformancePreset(_ preset: InstrumentPreset) {
        currentPreset = preset
        for layer in samplers.indices {
            loadPreset(preset, into: layer)
        }
    }

    private func configureFFT() {
        fftTap?.stop()
        fftTap = FFTTap(mixer, bufferSize: 2048) { [weak self] fftData in
            self?.handleFFT(fftData)
        }
        fftTap?.isNormalized = true
        fftTap?.start()
    }

    private func handleFFT(_ fftData: [Float]) {
        guard !fftData.isEmpty else { return }

        func average(_ range: Range<Int>) -> Double {
            let validRange = range.clamped(to: fftData.indices)
            guard !validRange.isEmpty else { return 0 }
            let total = validRange.reduce(Float(0)) { $0 + max(0, fftData[$1]) }
            return Double(total / Float(validRange.count)).clamped(to: 0...1)
        }

        let bass = average(2..<18)
        let mid = average(18..<86)
        let treble = average(86..<240)
        let amplitude = (bass * 0.55 + mid * 0.30 + treble * 0.15).clamped(to: 0...1)

        DispatchQueue.main.async {
            self.visualizerBands.bass = self.smooth(self.visualizerBands.bass, toward: bass)
            self.visualizerBands.mid = self.smooth(self.visualizerBands.mid, toward: mid)
            self.visualizerBands.treble = self.smooth(self.visualizerBands.treble, toward: treble)
            self.visualizerBands.amplitude = self.smooth(self.visualizerBands.amplitude, toward: amplitude)
            self.visualizerBands.lastVelocity *= 0.92
        }
    }

    func noteOn(_ note: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        guard samplers.indices.contains(currentLayer) else { return }

        applyHarmonyControls()
        let sourceLayer = currentLayer
        let sourcePreset = currentPreset
        let sourceVelocity = velocity
        let sourceChannel = channel
        let noteToken = UUID()
        let startedAt = Date()
        let activeNotes = Set(layers.flatMap(\.activeNotes)).union([note])
        let recentNotes = recentMelodyNotes + [note]
        let harmonySettingsSnapshot = harmonySettings
        let keySnapshot = harmony.snapshot(
            activeNotes: activeNotes,
            recentNotes: recentNotes,
            fallbackNote: note,
            lockedKey: harmonySettingsSnapshot.lockedKey
        )
        let correctedMelody = harmony.correctedMelodyNote(note, settings: harmonySettingsSnapshot, snapshot: keySnapshot)
        let melodyOctaveOffset = layers[sourceLayer].octaveOffset * 12
        let melodyNote = clampedMIDINote(Int(correctedMelody) + melodyOctaveOffset) ?? correctedMelody

        if !shouldSilenceLayer(sourceLayer) {
            samplers[sourceLayer].play(noteNumber: melodyNote, velocity: velocity, channel: channel)
        }

        if scoreEnabled {
            let mainScoreNote = ScoreNote(pitch: UInt8(melodyNote), startTime: startedAt, endTime: nil, layer: sourceLayer)
            scoreNotes.append(mainScoreNote)
            if scoreNotes.count > 120 {
                scoreNotes.removeFirst(scoreNotes.count - 120)
            }
        }

        let melodyVoice = PerformanceVoice(layer: sourceLayer, instrumentID: sourcePreset.id, note: melodyNote, channel: sourceChannel, velocityRatio: 1)
        let startedNote = StartedPerformanceNote(
            token: noteToken,
            startedAt: startedAt,
            startOffset: quantizedMeasureOffset(for: startedAt),
            sourceVelocity: sourceVelocity,
            instrumentName: sourcePreset.name,
            harmonyName: harmonySettingsSnapshot.style.name,
            rhythmName: selectedTimeSignature.label,
            voices: [melodyVoice]
        )
        startedNotes[note] = startedNote
        voicesBySourceNote[note] = [melodyVoice]
        layers[sourceLayer].activeNotes.insert(note)
        appendRecentMelodyNote(note)
        self.visualizerBands.lastVelocity = (Double(velocity) / 127).clamped(to: 0...1)
        self.visualizerBands.amplitude = max(self.visualizerBands.amplitude, self.visualizerBands.lastVelocity)
        self.visualizerBands.bass = max(self.visualizerBands.bass, self.visualizerBands.lastVelocity * 0.55)
        self.visualizerBands.mid = max(self.visualizerBands.mid, self.visualizerBands.lastVelocity * 0.75)
        self.visualizerBands.treble = max(self.visualizerBands.treble, self.visualizerBands.lastVelocity * 0.45)
        self.visualizerBands.triggerID += 1
        self.lastMIDIEvent = "Note \(note) velocity \(velocity)"

        scheduleHarmonyVoices(
            note: note,
            token: noteToken,
            sourceLayer: sourceLayer,
            sourceVelocity: sourceVelocity,
            sourceChannel: sourceChannel,
            sourcePreset: sourcePreset,
            harmonySettings: harmonySettingsSnapshot,
            keySnapshot: keySnapshot,
            melodyNote: melodyNote,
            startedAt: startedAt,
            activeNotes: activeNotes,
            recentNotes: recentNotes
        )
    }

    private func scheduleHarmonyVoices(
        note: MIDINoteNumber,
        token: UUID,
        sourceLayer: Int,
        sourceVelocity: MIDIVelocity,
        sourceChannel: MIDIChannel,
        sourcePreset: InstrumentPreset,
        harmonySettings: HarmonySettings,
        keySnapshot: HarmonyEngine.Snapshot,
        melodyNote: MIDINoteNumber,
        startedAt: Date,
        activeNotes: Set<MIDINoteNumber>,
        recentNotes: [MIDINoteNumber]
    ) {
        guard harmonySettings.style != .off, harmonySettings.maxVoices > 0 else {
            self.scaleLabel = keySnapshot.keyLabel
            self.chordLabel = keySnapshot.chordLabel
            self.harmonyLabel = "\(harmonySettings.style.name) C\(Int((self.harmonyComplexity * 100).rounded()))"
            return
        }

        Task.detached(priority: .userInitiated) { [harmony, harmonySettings] in
            let result = harmony.harmonize(
                melodyNote: melodyNote,
                activeNotes: activeNotes,
                recentNotes: recentNotes,
                settings: harmonySettings
            )
            let harmonyVelocity = MIDIVelocity((Double(sourceVelocity) * harmonySettings.velocityScale).rounded().clamped(to: 1...127))

            await MainActor.run {
                guard self.startedNotes[note]?.token == token else { return }

                var voices = [PerformanceVoice(
                    layer: sourceLayer,
                    instrumentID: sourcePreset.id,
                    note: melodyNote,
                    channel: sourceChannel,
                    velocityRatio: 1
                )]

                let orderedHarmonyNotes = self.orderedHarmonyNotes(result.notes, style: harmonySettings.style)
                for (offset, harmonyNote) in orderedHarmonyNotes.enumerated() {
                    let layer = (sourceLayer + offset + 1) % self.samplers.count
                    let harmonyOctaveOffset = self.layers[layer].octaveOffset * 12
                    let shiftedHarmonyNote = self.clampedMIDINote(Int(harmonyNote) + harmonyOctaveOffset) ?? harmonyNote

                    let baseStep = self.arpStepDuration()
                    let noteDelay = Double(offset) * baseStep

                    Task.detached(priority: .userInitiated) { [note, token, layer, shiftedHarmonyNote, harmonyVelocity, sourceChannel] in
                        if noteDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(noteDelay * 1_000_000_000))
                        }
                        await MainActor.run {
                            guard self.startedNotes[note]?.token == token else { return }

                            let maxVelocityOffset = 2 + Int(self.harmonyComplexity * 10)
                            let velocityOffset = Int.random(in: -maxVelocityOffset...maxVelocityOffset)
                            let humanizedVelocity = MIDIVelocity((Double(harmonyVelocity) + Double(velocityOffset)).rounded().clamped(to: 1...127))

                            if !self.shouldSilenceLayer(layer) {
                                self.samplers[layer].play(noteNumber: shiftedHarmonyNote, velocity: humanizedVelocity, channel: sourceChannel)
                            }

                            if self.scoreEnabled {
                                let harmonyScoreNote = ScoreNote(pitch: UInt8(shiftedHarmonyNote), startTime: Date(), endTime: nil, layer: layer)
                                self.scoreNotes.append(harmonyScoreNote)
                                if self.scoreNotes.count > 120 {
                                    self.scoreNotes.removeFirst(self.scoreNotes.count - 120)
                                }
                            }
                        }
                    }

                    voices.append(PerformanceVoice(
                        layer: layer,
                        instrumentID: sourcePreset.id,
                        note: shiftedHarmonyNote,
                        channel: sourceChannel,
                        velocityRatio: harmonySettings.velocityScale
                    ))
                }

                self.voicesBySourceNote[note] = voices
                if self.startedNotes[note]?.token == token {
                    self.startedNotes[note] = StartedPerformanceNote(
                        token: token,
                        startedAt: startedAt,
                        startOffset: self.quantizedMeasureOffset(for: startedAt),
                        sourceVelocity: sourceVelocity,
                        instrumentName: sourcePreset.name,
                        harmonyName: harmonySettings.style.name,
                        rhythmName: self.selectedTimeSignature.label,
                        voices: voices
                    )
                }
                self.scheduleGridHarmony(from: voices, sourceVelocity: sourceVelocity)
                self.scaleLabel = result.snapshot.keyLabel
                self.chordLabel = result.snapshot.chordLabel
                self.harmonyLabel = "\(harmonySettings.style.name) C\(Int((self.harmonyComplexity * 100).rounded()))"
            }
        }
    }

    private func orderedHarmonyNotes(_ notes: [MIDINoteNumber], style: HarmonyStyle) -> [MIDINoteNumber] {
        let sorted = notes.sorted()
        switch style {
        case .off:
            return []
        case .closeThirds:
            return sorted
        case .openFifths:
            return sorted
        case .fullTriad:
            return sorted
        case .dreamy:
            return sorted.reversed()
        case .seventh:
            return sorted
        case .octaves:
            return sorted
        }
    }

    func noteOff(_ note: MIDINoteNumber, channel: MIDIChannel) {
        let startedNote = startedNotes.removeValue(forKey: note)

        let melodyOctaveOffset = layers[currentLayer].octaveOffset * 12
        let melodyNote = clampedMIDINote(Int(note) + melodyOctaveOffset) ?? note
        if scoreEnabled, let idx = scoreNotes.lastIndex(where: { ($0.pitch == note || $0.pitch == melodyNote) && $0.endTime == nil }) {
            scoreNotes[idx].endTime = Date()
        }

        if let voices = voicesBySourceNote.removeValue(forKey: note) {
            for voice in voices where samplers.indices.contains(voice.layer) {
                samplers[voice.layer].stop(noteNumber: voice.note, channel: voice.channel)
                if scoreEnabled, let idx = scoreNotes.lastIndex(where: { $0.pitch == voice.note && $0.endTime == nil }) {
                    scoreNotes[idx].endTime = Date()
                }
            }
        } else if samplers.indices.contains(currentLayer) {
            samplers[currentLayer].stop(noteNumber: note, channel: channel)
        } else {
            for sampler in samplers {
                sampler.stop(noteNumber: note, channel: channel)
            }
        }

        if let startedNote {
            let duration = max(0.06, min(8, Date().timeIntervalSince(startedNote.startedAt)))
            capturePhraseNote(startedNote, duration: quantizedDuration(duration))
            recordPlayedEvent(note: note, startedNote: startedNote)
        }

        for layer in self.layers.indices {
            self.layers[layer].activeNotes.remove(note)
        }
        if activeOneShotNote?.note == note, activeOneShotNote?.channel == channel {
            activeOneShotNote = nil
        }
        self.lastMIDIEvent = "Note off \(note)"
    }

    private func handlePadNoteOn(note: MIDINoteNumber) -> Bool {
        guard let padIndex = mappingConfig.padMappings[Int(note)] else { return false }
        guard InstrumentPreset.starterPresets.indices.contains(padIndex) else { return false }

        activePadNotes.insert(note)
        
        let pad0Note = mappingConfig.padMappings.first(where: { $0.value == 0 })?.key
        let pad15Note = mappingConfig.padMappings.first(where: { $0.value == 15 })?.key
        if let pad0Note, let pad15Note, activePadNotes.contains(MIDINoteNumber(pad0Note)), activePadNotes.contains(MIDINoteNumber(pad15Note)) {
            panic()
            self.lastPadIndex = nil
            self.lastMIDIEvent = "Pad 1 + 16: all notes off"
            return true
        }

        if padIndex == 12 {
            self.lastPadIndex = padIndex
            self.lastMIDIEvent = "Layer select"
            return true
        }

        if padIndex == 13 {
            self.lastPadIndex = padIndex
            self.lastMIDIEvent = "Harmony select"
            return true
        }

        let pad12Note = mappingConfig.padMappings.first(where: { $0.value == 12 })?.key
        if let pad12Note, activePadNotes.contains(MIDINoteNumber(pad12Note)) {
            if padIndex == 14 {
                loopEnabled.toggle()
                self.lastPadIndex = padIndex
                self.lastMIDIEvent = "Loop: \(loopEnabled ? "ON" : "OFF")"
                publishStatus("Loop Playback \(loopEnabled ? "Enabled" : "Disabled")")
                return true
            }
            if padIndex == 15 {
                drumEnabled.toggle()
                self.lastPadIndex = padIndex
                self.lastMIDIEvent = "Drums: \(drumEnabled ? "ON" : "OFF")"
                publishStatus("Drumbeat \(drumEnabled ? "Enabled" : "Disabled")")
                return true
            }
            guard padIndex < samplers.count else { return true }
            selectLayer(padIndex)
            self.lastPadIndex = padIndex
            self.lastMIDIEvent = "Layer \(self.currentLayer + 1)"
            return true
        }

        let pad13Note = mappingConfig.padMappings.first(where: { $0.value == 13 })?.key
        if let pad13Note, activePadNotes.contains(MIDINoteNumber(pad13Note)) {
            guard padIndex < HarmonyStyle.allCases.count else { return true }
            selectHarmonyStyle(padIndex)
            return true
        }

        let preset = InstrumentPreset.starterPresets[padIndex]
        loadPerformancePreset(preset)
        self.lastPadIndex = padIndex
        self.lastMIDIEvent = "Instrument: \(preset.name)"
        return true
    }

    private func learnPadsFrom(note: MIDINoteNumber, channel: MIDIChannel) {
        guard !isLikelyKeyboardChannel(channel) else { return }
        if mappingConfig.padMappings[Int(note)] != nil {
            padChannelNumber = Int(channel) + 1
        }
    }

    private func handlePadNoteOff(note: MIDINoteNumber) -> Bool {
        guard mappingConfig.padMappings[Int(note)] != nil else { return false }
        activePadNotes.remove(note)
        return true
    }

    private func handleControl(_ controller: MIDIByte, value: MIDIByte) {
        let normalized = Double(value) / 127

        if controller == 120 || controller == 123 {
            self.panic()
        } else if let target = self.mappingConfig.ccMappings[Int(controller)] {
            switch target {
            case .brightness:
                self.controls.brightness = normalized
            case .gravity:
                self.controls.gravity = normalized
            case .particleSize:
                self.controls.particleSize = normalized
                self.harmonySettings.spread = Int((normalized * 4).rounded()).clamped(to: 0...4)
                self.harmonyLabel = "\(self.harmonySettings.style.name) S\(self.harmonySettings.spread)"
            case .trail:
                self.controls.trail = normalized
                self.harmonySettings.maxVoices = Int((normalized * 4).rounded()).clamped(to: 1...4)
                self.harmonyLabel = "\(self.harmonySettings.style.name) V\(self.harmonySettings.maxVoices)"
            }
        }

        self.lastMIDIEvent = "CC \(controller): \(value)"
    }

    private func publishStatus(_ message: String) {
        self.status = message
    }

    private func smooth(_ current: Double, toward next: Double) -> Double {
        current * 0.82 + next * 0.18
    }

    private func appendRecentMelodyNote(_ note: MIDINoteNumber) {
        recentMelodyNotes.append(note)
        if recentMelodyNotes.count > 12 {
            recentMelodyNotes.removeFirst(recentMelodyNotes.count - 12)
        }
    }

    private func applyHarmonyControls() {
        harmonySettings.lockedKey = HarmonyEngine.KeySignature(rootPitchClass: keyRootIndex, mode: keyMode)
        harmonySettings.maxVoices = Int((1 + harmonyComplexity * 3).rounded()).clamped(to: 1...4)
        harmonySettings.spread = Int((harmonyComplexity * 4).rounded()).clamped(to: 0...4)
        harmonySettings.velocityScale = 0.58 + harmonyComplexity * 0.24
    }

    private func scheduleGridHarmony(from voices: [PerformanceVoice], sourceVelocity: MIDIVelocity) {
        let harmonyVoices = Array(voices.dropFirst())
        guard !harmonyVoices.isEmpty, harmonyComplexity > 0.18 else { return }

        let generation = loopGeneration
        let step = arpStepDuration()
        let steps = Int((1 + harmonyComplexity * 5).rounded()).clamped(to: 1...6)

        for index in 0..<steps {
            let voice = harmonyVoices[index % harmonyVoices.count]
            let delay = step * Double(index + 1)
            let gain = 0.38 + harmonyComplexity * 0.34
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard self.hasStarted, self.loopGeneration == generation else { return }
                guard !self.shouldSilenceLayer(voice.layer) else { return }
                let layerVolume = self.layers[voice.layer].volume
                let velocity = MIDIVelocity((Double(sourceVelocity) * voice.velocityRatio * gain * layerVolume).rounded().clamped(to: 1...127))
                if self.loopSamplers.indices.contains(voice.instrumentID) {
                    self.loopSamplers[voice.instrumentID].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(min(step * 0.75, 0.35) * 1_000_000_000))
                        guard self.loopGeneration == generation, self.loopSamplers.indices.contains(voice.instrumentID) else { return }
                        self.loopSamplers[voice.instrumentID].stop(noteNumber: voice.note, channel: voice.channel)
                    }
                }
            }
        }
    }

    private func gridStepDuration() -> TimeInterval {
        let quarter = 60 / tempoBPM
        let beat = quarter * (4 / Double(selectedTimeSignature.beatUnit))
        return beat / (harmonyComplexity > 0.70 ? 2 : 1)
    }

    /// Rhythmic spacing for the arpeggiator. Plays as a quarter-note (1/4) arp
    /// when gentle and an eighth-note (1/8) arp when busy — never faster, so the
    /// harmony notes step out as a melody instead of stacking on the beat.
    private func arpStepDuration() -> TimeInterval {
        let beat = max(0.12, (60 / tempoBPM) * (4 / Double(selectedTimeSignature.beatUnit)))
        return harmonyComplexity > 0.5 ? beat * 0.5 : beat
    }

    private func capturePhraseNote(_ startedNote: StartedPerformanceNote, duration: TimeInterval) {
        guard loopEnabled, tempoBPM > 0 else { return }

        let measureIndex = currentMeasureIndex()
        if measureIndex != phraseMeasureIndex {
            phraseNotes.removeAll()
            phraseMeasureIndex = measureIndex
        }

        phraseNotes.append(
            CapturedPhraseNote(
                startOffset: startedNote.startOffset,
                duration: duration,
                sourceVelocity: startedNote.sourceVelocity,
                voices: startedNote.voices
            )
        )

        self.phraseStatus = "Phrase \(self.phraseNotes.count) note\(self.phraseNotes.count == 1 ? "" : "s")"
        scheduleCurrentPhraseIfNeeded()
    }

    private func scheduleCurrentPhraseIfNeeded() {
        phraseScheduleGeneration += 1
        let generation = phraseScheduleGeneration
        let delay = delayToNextMeasure(from: Date())

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard self.hasStarted, self.loopEnabled, self.phraseScheduleGeneration == generation else { return }
            self.schedulePhraseRepeats(notes: self.phraseNotes, generation: self.loopGeneration)
        }
    }

    private func schedulePhraseRepeats(notes: [CapturedPhraseNote], generation: Int) {
        guard !notes.isEmpty else { return }

        let loopInterval = measureDuration()
        phraseNotes.removeAll()
        self.phraseStatus = "Looping phrase"

        for repeatIndex in 1...5 {
            let gain = pow(0.88, Double(repeatIndex))
            for note in notes {
                let delay = note.startOffset + loopInterval * Double(repeatIndex - 1)
                let replayDuration = min(note.duration, loopInterval * 0.92)

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard self.hasStarted, self.loopGeneration == generation else { return }
                    self.playLoopVoices(note.voices, sourceVelocity: note.sourceVelocity, gain: gain)

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(replayDuration * 1_000_000_000))
                        guard self.loopGeneration == generation else { return }
                        self.stopLoopVoices(note.voices)
                    }
                }
            }
        }
    }

    private func playLoopVoices(_ voices: [PerformanceVoice], sourceVelocity: MIDIVelocity, gain: Double) {
        for voice in voices where samplers.indices.contains(voice.layer) {
            guard !shouldSilenceLayer(voice.layer) else { continue }
            let layerVolume = layers[voice.layer].volume
            let velocity = MIDIVelocity((Double(sourceVelocity) * voice.velocityRatio * gain * layerVolume).rounded().clamped(to: 1...127))
            if loopSamplers.indices.contains(voice.instrumentID) {
                loopSamplers[voice.instrumentID].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
            } else {
                samplers[voice.layer].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
            }
        }

        self.visualizerBands.lastVelocity = max(self.visualizerBands.lastVelocity, gain)
        self.visualizerBands.amplitude = max(self.visualizerBands.amplitude, gain * 0.7)
        self.visualizerBands.triggerID += 1
        self.lastMIDIEvent = "Loop x\(String(format: "%.2f", gain))"
    }

    private func stopLoopVoices(_ voices: [PerformanceVoice]) {
        for voice in voices where samplers.indices.contains(voice.layer) {
            if loopSamplers.indices.contains(voice.instrumentID) {
                loopSamplers[voice.instrumentID].stop(noteNumber: voice.note, channel: voice.channel)
            } else {
                samplers[voice.layer].stop(noteNumber: voice.note, channel: voice.channel)
            }
        }
    }

    private func startDrumLoop() {
        drumGeneration += 1
        measureAnchor = Date()
        scheduleDrumBeat(step: 0, generation: drumGeneration)
    }

    private func scheduleDrumBeat(step: Int, generation: Int) {
        guard hasStarted, generation == drumGeneration else { return }

        if drumEnabled {
            playDrumStep(step)
        }

        let beatDuration = (60 / tempoBPM) * (4 / Double(selectedTimeSignature.beatUnit))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(beatDuration * 1_000_000_000))
            guard hasStarted, generation == drumGeneration else { return }
            let next = (step + 1) % max(1, self.selectedTimeSignature.beats)
            self.scheduleDrumBeat(step: next, generation: generation)
        }
    }

    private func playDrumStep(_ step: Int) {
        let notes = drumNotes(for: step)

        for note in notes {
            drumSampler.play(noteNumber: note.0, velocity: note.1, channel: 9)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000) // 0.08s
                self.drumSampler.stop(noteNumber: note.0, channel: 9)
            }
        }
    }

    private func drumNotes(for step: Int) -> [(MIDINoteNumber, MIDIVelocity)] {
        switch selectedTimeSignature.label {
        case "3/4":
            return [
                (36, step == 0 ? 96 : 52),
                (42, 38),
                (38, step == 1 ? 64 : 0)
            ].filter { $0.1 > 0 }
        case "6/8":
            return [
                (36, step == 0 ? 94 : (step == 3 ? 70 : 0)),
                (42, step % 3 == 0 ? 46 : 34),
                (38, step == 3 ? 62 : 0)
            ].filter { $0.1 > 0 }
        case "3/8":
            return [
                (36, step == 0 ? 88 : 0),
                (42, 36),
                (38, step == 2 ? 52 : 0)
            ].filter { $0.1 > 0 }
        default:
            return [
                (36, step == 0 ? 98 : (step == 2 ? 62 : 0)),
                (42, 42),
                (38, step == 2 ? 78 : 0)
            ].filter { $0.1 > 0 }
        }
    }

    private func measureDuration() -> TimeInterval {
        (60 / tempoBPM) * selectedTimeSignature.measureBeatsInQuarterNotes
    }

    private func quantizedMeasureOffset(for date: Date) -> TimeInterval {
        let measure = measureDuration()
        guard measure > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(measureAnchor)
        let offset = elapsed.truncatingRemainder(dividingBy: measure)
        let positiveOffset = offset < 0 ? offset + measure : offset
        let grid = gridStepDuration()
        guard grid > 0 else { return positiveOffset }
        let quantized = (positiveOffset / grid).rounded() * grid
        return min(quantized, measure - 0.001)
    }

    private func quantizedDuration(_ duration: TimeInterval) -> TimeInterval {
        let grid = gridStepDuration()
        guard grid > 0 else { return duration }
        return max(grid * 0.5, min(measureDuration() * 0.92, (duration / grid).rounded() * grid))
    }

    private func oneShotHoldDuration() -> TimeInterval {
        guard tempoBPM > 0 else { return 0.75 }
        let beat = max(0.12, (60 / tempoBPM) * (4 / Double(selectedTimeSignature.beatUnit)))
        // Gate a single click to a whole number of beats — long enough for the
        // arpeggio to step out, then released cleanly on the beat.
        let arpSpan = arpStepDuration() * Double(max(1, harmonySettings.maxVoices))
        let beatsNeeded = max(1.0, (arpSpan / beat).rounded(.up))
        return beat * beatsNeeded
    }

    private func delayToNextGridBoundary(from date: Date) -> TimeInterval {
        let grid = gridStepDuration()
        guard grid > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(measureAnchor)
        let offset = elapsed.truncatingRemainder(dividingBy: grid)
        return offset <= 0 ? 0 : grid - offset
    }

    private func delayToNextMeasure(from date: Date) -> TimeInterval {
        let measure = measureDuration()
        guard measure > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(measureAnchor)
        let offset = elapsed.truncatingRemainder(dividingBy: measure)
        return offset <= 0 ? 0 : measure - offset
    }

    private func currentMeasureIndex() -> Int {
        let measure = measureDuration()
        guard measure > 0 else { return 0 }
        return max(0, Int(Date().timeIntervalSince(measureAnchor) / measure))
    }

    private func selectHarmonyStyle(_ padIndex: Int) {
        let styles = HarmonyStyle.allCases
        let style = styles[padIndex % styles.count]
        harmonySettings.style = style
        self.lastPadIndex = padIndex
        self.harmonyLabel = style.name
        self.lastMIDIEvent = "Harmony: \(style.name)"
    }

    private func recordPlayedEvent(note: MIDINoteNumber, startedNote: StartedPerformanceNote) {
        let event = PlayedEvent(
            noteName: noteName(note),
            instrumentName: startedNote.instrumentName,
            harmonyName: startedNote.harmonyName,
            rhythmName: startedNote.rhythmName
        )

        self.playedEvents.insert(event, at: 0)
        if self.playedEvents.count > 8 {
            self.playedEvents.removeLast(self.playedEvents.count - 8)
        }
    }

    private func noteName(_ note: MIDINoteNumber) -> String {
        let names = HarmonyEngine.KeySignature.pitchNames
        let octave = Int(note / 12) - 1
        return "\(names[Int(note % 12)])\(octave)"
    }

    private func logMIDI(_ label: String) {
        self.midiEvents.insert(MIDIEventLog(label: label), at: 0)
        if self.midiEvents.count > 6 {
            self.midiEvents.removeLast(self.midiEvents.count - 6)
        }
    }

    private func isLikelyKeyboardChannel(_ channel: MIDIChannel) -> Bool {
        channel == 0
    }

    private func clampedMIDINote(_ value: Int) -> MIDINoteNumber? {
        guard (0...127).contains(value) else { return nil }
        return MIDINoteNumber(value)
    }
}

extension AudioManager: MIDIListener {
    nonisolated func receivedMIDINoteOn(
        noteNumber: MIDINoteNumber,
        velocity: MIDIVelocity,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        Task { @MainActor in
            self.handleMIDINoteOn(noteNumber: noteNumber, velocity: velocity, channel: channel)
        }
    }

    private func handleMIDINoteOn(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        logMIDI("on note \(noteNumber) ch \(channel + 1) vel \(velocity)")
        guard velocity > 0 else {
            noteOff(noteNumber, channel: channel)
            return
        }

        if let slot = activeLearnSlot {
            switch slot {
            case .pad(let index):
                self.mappingConfig.padMappings = self.mappingConfig.padMappings.filter { $0.value != index && $0.key != Int(noteNumber) }
                self.mappingConfig.padMappings[Int(noteNumber)] = index
                self.saveMappingConfig()
                self.activeLearnSlot = nil
                self.publishStatus("Mapped Pad \(index + 1) to Note \(noteNumber)")
                return
            default:
                break
            }
        }

        learnPadsFrom(note: noteNumber, channel: channel)
        if channel == padChannel, handlePadNoteOn(note: noteNumber) {
            return
        } else {
            noteOn(noteNumber, velocity: velocity, channel: channel)
        }
    }

    nonisolated func receivedMIDINoteOff(
        noteNumber: MIDINoteNumber,
        velocity: MIDIVelocity,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        Task { @MainActor in
            self.handleMIDINoteOff(noteNumber: noteNumber, velocity: velocity, channel: channel)
        }
    }

    private func handleMIDINoteOff(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        logMIDI("off note \(noteNumber) ch \(channel + 1)")
        if channel == padChannel, handlePadNoteOff(note: noteNumber) {
            return
        } else {
            noteOff(noteNumber, channel: channel)
        }
    }

    nonisolated func receivedMIDIController(
        _ controller: MIDIByte,
        value: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        Task { @MainActor in
            self.handleMIDIController(controller, value: value, channel: channel)
        }
    }

    private func handleMIDIController(_ controller: MIDIByte, value: MIDIByte, channel: MIDIChannel) {
        logMIDI("cc \(controller) ch \(channel + 1) val \(value)")
        
        if let slot = activeLearnSlot {
            switch slot {
            case .cc(let target):
                self.mappingConfig.ccMappings = self.mappingConfig.ccMappings.filter { $0.value != target && $0.key != Int(controller) }
                self.mappingConfig.ccMappings[Int(controller)] = target
                self.saveMappingConfig()
                self.activeLearnSlot = nil
                self.publishStatus("Mapped CC \(controller) to \(target.rawValue)")
                return
            default:
                break
            }
        }

        handleControl(controller, value: value)
    }

    nonisolated func receivedMIDIAftertouch(
        noteNumber: MIDINoteNumber,
        pressure: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    nonisolated func receivedMIDIAftertouch(
        _ pressure: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    nonisolated func receivedMIDIPitchWheel(
        _ pitchWheelValue: MIDIWord,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    nonisolated func receivedMIDIProgramChange(
        _ program: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    nonisolated func receivedMIDISystemCommand(
        _ data: [MIDIByte],
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    nonisolated func receivedMIDISetupChange() {
        Task { @MainActor in
            guard self.hasStarted else { return }
            self.openMIDIInputs()
            self.publishMIDIInputStatus()
        }
    }

    nonisolated func receivedMIDIPropertyChange(propertyChangeInfo: MIDIObjectPropertyChangeNotification) {}

    nonisolated func receivedMIDINotification(notification: MIDINotification) {}
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
