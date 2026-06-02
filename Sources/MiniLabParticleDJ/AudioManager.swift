import AudioKit
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

private struct PerformanceVoice {
    let layer: Int
    let instrumentID: Int
    let note: MIDINoteNumber
    let channel: MIDIChannel
    let velocityRatio: Double
}

private struct StartedPerformanceNote {
    let startedAt: Date
    let sourceVelocity: MIDIVelocity
    let instrumentName: String
    let harmonyName: String
    let rhythmName: String
    let voices: [PerformanceVoice]
}

final class AudioManager: ObservableObject {
    let padBaseNote: MIDINoteNumber = 36
    let padChannel: MIDIChannel = 9

    @Published var currentLayer = 0
    @Published var layers: [LayerState]
    @Published var visualizerBands = VisualizerBands()
    @Published var controls = PerformanceControls()
    @Published var tempoBPM: Double = 96
    @Published var selectedTimeSignature = TimeSignatureOption.options[0]
    @Published var loopEnabled = true
    @Published var drumEnabled = true
    @Published var harmonyComplexity: Double = 0.45
    @Published var keyRootIndex = 0
    @Published var keyMode = HarmonyEngine.ScaleMode.major
    @Published var scaleLabel = "C Major"
    @Published var chordLabel = "No Chord"
    @Published var harmonyLabel = "Close 3rds"
    @Published var status = "Audio engine idle"
    @Published var lastMIDIEvent = "Waiting for MiniLab Mk2"
    @Published var lastPadIndex: Int?
    @Published var playedEvents: [PlayedEvent] = []

    private let engine = AudioEngine()
    private let mixer = Mixer()
    private let midi = MIDI()
    private let harmony = HarmonyEngine()
    private var samplers: [AppleSampler] = []
    private var loopSamplers: [AppleSampler] = []
    private let drumSampler = AppleSampler()
    private var fftTap: FFTTap?
    private var loadedCustomInstrumentURLs: [Int: URL] = [:]
    private var voicesBySourceNote: [MIDINoteNumber: [PerformanceVoice]] = [:]
    private var startedNotes: [MIDINoteNumber: StartedPerformanceNote] = [:]
    private var activePadNotes: Set<MIDINoteNumber> = []
    private var recentMelodyNotes: [MIDINoteNumber] = []
    private var harmonySettings = HarmonySettings()
    private var loopGeneration = 0
    private var drumGeneration = 0
    private var currentPreset = InstrumentPreset.starterPresets[0]
    private var hasStarted = false

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
            mixer.addInput(sampler)
        }

        for _ in InstrumentPreset.starterPresets {
            let sampler = AppleSampler()
            loopSamplers.append(sampler)
            mixer.addInput(sampler)
        }

        mixer.addInput(drumSampler)
        engine.output = mixer
        midi.addListener(self)
    }

    func start() {
        guard !hasStarted else { return }
        do {
            try engine.start()
            hasStarted = true
            midi.openInput()
            configureFFT()
            loadStarterPresets()
            loadLoopPresets()
            loadDrums()
            startDrumLoop()
            publishStatus("Engine running. Listening to Core MIDI inputs.")
        } catch {
            publishStatus("Engine failed: \(error.localizedDescription)")
        }
    }

    func stop() {
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
        voicesBySourceNote.removeAll()
        startedNotes.removeAll()
        recentMelodyNotes.removeAll()
        DispatchQueue.main.async {
            for layer in self.layers.indices {
                self.layers[layer].activeNotes.removeAll()
            }
            self.lastMIDIEvent = "All notes off"
        }
    }

    deinit {
        stop()
    }

    func selectLayer(_ layer: Int) {
        guard layers.indices.contains(layer) else { return }
        currentLayer = layer
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
            DispatchQueue.main.async {
                self.layers[layer].name = url.deletingPathExtension().lastPathComponent
                self.layers[layer].isLoaded = true
                self.publishStatus("Loaded \(url.lastPathComponent) into layer \(layer + 1).")
            }
        } catch {
            publishStatus("Could not load \(url.lastPathComponent): \(error.localizedDescription)")
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

            DispatchQueue.main.async {
                self.loadedCustomInstrumentURLs[layer] = nil
                self.layers[layer].preset = preset
                self.layers[layer].name = preset.name
                self.layers[layer].isLoaded = true
                self.publishStatus("Layer \(layer + 1): \(preset.name)")
            }
        } catch {
            publishStatus("Could not load \(preset.name): \(error.localizedDescription)")
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

    private func noteOn(_ note: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        guard samplers.indices.contains(currentLayer) else { return }

        applyHarmonyControls()
        let activeNotes = Set(layers.flatMap(\.activeNotes)).union([note])
        appendRecentMelodyNote(note)

        let result = harmony.harmonize(
            melodyNote: note,
            activeNotes: activeNotes,
            recentNotes: recentMelodyNotes,
            settings: harmonySettings
        )
        let melodyNote = harmony.correctedMelodyNote(note, settings: harmonySettings, snapshot: result.snapshot)
        samplers[currentLayer].play(noteNumber: melodyNote, velocity: velocity, channel: channel)

        let harmonyVelocity = MIDIVelocity((Double(velocity) * harmonySettings.velocityScale).rounded().clamped(to: 1...127))
        var voices: [PerformanceVoice] = [
            PerformanceVoice(layer: currentLayer, instrumentID: currentPreset.id, note: melodyNote, channel: channel, velocityRatio: 1)
        ]

        for (offset, harmonyNote) in result.notes.enumerated() {
            let layer = (currentLayer + offset + 1) % samplers.count
            samplers[layer].play(noteNumber: harmonyNote, velocity: harmonyVelocity, channel: channel)
            voices.append(PerformanceVoice(layer: layer, instrumentID: currentPreset.id, note: harmonyNote, channel: channel, velocityRatio: harmonySettings.velocityScale))
        }

        voicesBySourceNote[note] = voices
        startedNotes[note] = StartedPerformanceNote(
            startedAt: Date(),
            sourceVelocity: velocity,
            instrumentName: currentPreset.name,
            harmonyName: harmonySettings.style.name,
            rhythmName: selectedTimeSignature.label,
            voices: voices
        )
        scheduleGridHarmony(from: voices, sourceVelocity: velocity)

        DispatchQueue.main.async {
            self.layers[self.currentLayer].activeNotes.insert(note)
            self.scaleLabel = result.snapshot.keyLabel
            self.chordLabel = result.snapshot.chordLabel
            self.harmonyLabel = "\(self.harmonySettings.style.name) C\(Int((self.harmonyComplexity * 100).rounded()))"
            self.visualizerBands.lastVelocity = (Double(velocity) / 127).clamped(to: 0...1)
            self.visualizerBands.amplitude = max(self.visualizerBands.amplitude, self.visualizerBands.lastVelocity)
            self.visualizerBands.bass = max(self.visualizerBands.bass, self.visualizerBands.lastVelocity * 0.55)
            self.visualizerBands.mid = max(self.visualizerBands.mid, self.visualizerBands.lastVelocity * 0.75)
            self.visualizerBands.treble = max(self.visualizerBands.treble, self.visualizerBands.lastVelocity * 0.45)
            self.visualizerBands.triggerID += 1
            self.lastMIDIEvent = "Note \(note) velocity \(velocity)"
        }
    }

    private func noteOff(_ note: MIDINoteNumber, channel: MIDIChannel) {
        let startedNote = startedNotes.removeValue(forKey: note)

        if let voices = voicesBySourceNote.removeValue(forKey: note) {
            for voice in voices where samplers.indices.contains(voice.layer) {
                samplers[voice.layer].stop(noteNumber: voice.note, channel: voice.channel)
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
            scheduleLoopEchoes(for: startedNote, duration: duration)
            recordPlayedEvent(note: note, startedNote: startedNote)
        }

        DispatchQueue.main.async {
            for layer in self.layers.indices {
                self.layers[layer].activeNotes.remove(note)
            }
            self.lastMIDIEvent = "Note off \(note)"
        }
    }

    private func handlePadNoteOn(note: MIDINoteNumber) -> Bool {
        guard note >= padBaseNote else { return false }
        let padIndex = Int(note - padBaseNote)
        guard InstrumentPreset.starterPresets.indices.contains(padIndex) else { return false }

        activePadNotes.insert(note)
        if activePadNotes.contains(padBaseNote), activePadNotes.contains(padBaseNote + 15) {
            panic()
            DispatchQueue.main.async {
                self.lastPadIndex = nil
                self.lastMIDIEvent = "Pad 1 + 16: all notes off"
            }
            return true
        }

        if padIndex == 12 {
            DispatchQueue.main.async {
                self.lastPadIndex = padIndex
                self.lastMIDIEvent = "Layer select"
            }
            return true
        }

        if padIndex == 13 {
            DispatchQueue.main.async {
                self.lastPadIndex = padIndex
                self.lastMIDIEvent = "Harmony select"
            }
            return true
        }

        if activePadNotes.contains(padBaseNote + 12) {
            guard padIndex < samplers.count else { return true }
            selectLayer(padIndex)
            DispatchQueue.main.async {
                self.lastPadIndex = padIndex
                self.lastMIDIEvent = "Layer \(self.currentLayer + 1)"
            }
            return true
        }

        if activePadNotes.contains(padBaseNote + 13) {
            guard padIndex < HarmonyStyle.allCases.count else { return true }
            selectHarmonyStyle(padIndex)
            return true
        }

        let preset = InstrumentPreset.starterPresets[padIndex]
        loadPerformancePreset(preset)
        DispatchQueue.main.async {
            self.lastPadIndex = padIndex
            self.lastMIDIEvent = "Instrument: \(preset.name)"
        }
        return true
    }

    private func handlePadNoteOff(note: MIDINoteNumber) -> Bool {
        guard note >= padBaseNote else { return false }
        let padIndex = Int(note - padBaseNote)
        guard InstrumentPreset.starterPresets.indices.contains(padIndex) else { return false }

        activePadNotes.remove(note)
        return true
    }

    private func handleControl(_ controller: MIDIByte, value: MIDIByte) {
        let normalized = Double(value) / 127

        DispatchQueue.main.async {
            switch controller {
            case 120, 123:
                self.panic()
            case 74:
                self.controls.brightness = normalized
            case 71:
                self.controls.gravity = normalized
            case 73:
                self.controls.particleSize = normalized
                self.harmonySettings.spread = Int((normalized * 4).rounded()).clamped(to: 0...4)
                self.harmonyLabel = "\(self.harmonySettings.style.name) S\(self.harmonySettings.spread)"
            case 72:
                self.controls.trail = normalized
                self.harmonySettings.maxVoices = Int((normalized * 4).rounded()).clamped(to: 1...4)
                self.harmonyLabel = "\(self.harmonySettings.style.name) V\(self.harmonySettings.maxVoices)"
            default:
                break
            }

            self.lastMIDIEvent = "CC \(controller): \(value)"
        }
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async {
            self.status = message
        }
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
        let step = gridStepDuration()
        let steps = Int((1 + harmonyComplexity * 5).rounded()).clamped(to: 1...6)

        for index in 0..<steps {
            let voice = harmonyVoices[index % harmonyVoices.count]
            let delay = step * Double(index + 1)
            let gain = 0.38 + harmonyComplexity * 0.34
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.hasStarted, self.loopGeneration == generation else { return }
                let velocity = MIDIVelocity((Double(sourceVelocity) * voice.velocityRatio * gain).rounded().clamped(to: 1...127))
                if self.loopSamplers.indices.contains(voice.instrumentID) {
                    self.loopSamplers[voice.instrumentID].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
                    DispatchQueue.main.asyncAfter(deadline: .now() + min(step * 0.75, 0.35)) { [weak self] in
                        guard let self, self.loopGeneration == generation, self.loopSamplers.indices.contains(voice.instrumentID) else { return }
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

    private func scheduleLoopEchoes(for startedNote: StartedPerformanceNote, duration: TimeInterval) {
        guard loopEnabled, tempoBPM > 0 else { return }

        let generation = loopGeneration
        let loopInterval = (60 / tempoBPM) * selectedTimeSignature.measureBeatsInQuarterNotes
        let replayDuration = min(duration, loopInterval * 0.92)

        for repeatIndex in 1...5 {
            let delay = loopInterval * Double(repeatIndex)
            let gain = pow(0.88, Double(repeatIndex))

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.hasStarted, self.loopGeneration == generation else { return }
                self.playLoopVoices(startedNote.voices, sourceVelocity: startedNote.sourceVelocity, gain: gain)

                DispatchQueue.main.asyncAfter(deadline: .now() + replayDuration) { [weak self] in
                    guard let self, self.loopGeneration == generation else { return }
                    self.stopLoopVoices(startedNote.voices)
                }
            }
        }
    }

    private func playLoopVoices(_ voices: [PerformanceVoice], sourceVelocity: MIDIVelocity, gain: Double) {
        for voice in voices where samplers.indices.contains(voice.layer) {
            let velocity = MIDIVelocity((Double(sourceVelocity) * voice.velocityRatio * gain).rounded().clamped(to: 1...127))
            if loopSamplers.indices.contains(voice.instrumentID) {
                loopSamplers[voice.instrumentID].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
            } else {
                samplers[voice.layer].play(noteNumber: voice.note, velocity: velocity, channel: voice.channel)
            }
        }

        DispatchQueue.main.async {
            self.visualizerBands.lastVelocity = max(self.visualizerBands.lastVelocity, gain)
            self.visualizerBands.amplitude = max(self.visualizerBands.amplitude, gain * 0.7)
            self.visualizerBands.triggerID += 1
            self.lastMIDIEvent = "Loop x\(String(format: "%.2f", gain))"
        }
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
        scheduleDrumBeat(step: 0, generation: drumGeneration)
    }

    private func scheduleDrumBeat(step: Int, generation: Int) {
        guard hasStarted, generation == drumGeneration else { return }

        if drumEnabled {
            playDrumStep(step)
        }

        let beatDuration = (60 / tempoBPM) * (4 / Double(selectedTimeSignature.beatUnit))
        DispatchQueue.main.asyncAfter(deadline: .now() + beatDuration) { [weak self] in
            guard let self else { return }
            let next = (step + 1) % max(1, self.selectedTimeSignature.beats)
            self.scheduleDrumBeat(step: next, generation: generation)
        }
    }

    private func playDrumStep(_ step: Int) {
        let isDownbeat = step == 0
        let isBackbeat = selectedTimeSignature.beats >= 4 ? step == 2 : step == 1
        let notes: [(MIDINoteNumber, MIDIVelocity)] = [
            (36, isDownbeat ? 96 : 58),
            (42, 42),
            (38, isBackbeat ? 78 : 0)
        ].filter { $0.1 > 0 }

        for note in notes {
            drumSampler.play(noteNumber: note.0, velocity: note.1, channel: 9)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.drumSampler.stop(noteNumber: note.0, channel: 9)
            }
        }
    }

    private func selectHarmonyStyle(_ padIndex: Int) {
        let styles = HarmonyStyle.allCases
        let style = styles[padIndex % styles.count]
        harmonySettings.style = style
        DispatchQueue.main.async {
            self.lastPadIndex = padIndex
            self.harmonyLabel = style.name
            self.lastMIDIEvent = "Harmony: \(style.name)"
        }
    }

    private func recordPlayedEvent(note: MIDINoteNumber, startedNote: StartedPerformanceNote) {
        let event = PlayedEvent(
            noteName: noteName(note),
            instrumentName: startedNote.instrumentName,
            harmonyName: startedNote.harmonyName,
            rhythmName: startedNote.rhythmName
        )

        DispatchQueue.main.async {
            self.playedEvents.insert(event, at: 0)
            if self.playedEvents.count > 8 {
                self.playedEvents.removeLast(self.playedEvents.count - 8)
            }
        }
    }

    private func noteName(_ note: MIDINoteNumber) -> String {
        let names = HarmonyEngine.KeySignature.pitchNames
        let octave = Int(note / 12) - 1
        return "\(names[Int(note % 12)])\(octave)"
    }
}

extension AudioManager: MIDIListener {
    func receivedMIDINoteOn(
        noteNumber: MIDINoteNumber,
        velocity: MIDIVelocity,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        guard velocity > 0 else {
            noteOff(noteNumber, channel: channel)
            return
        }

        if channel == padChannel, handlePadNoteOn(note: noteNumber) {
            return
        } else {
            noteOn(noteNumber, velocity: velocity, channel: channel)
        }
    }

    func receivedMIDINoteOff(
        noteNumber: MIDINoteNumber,
        velocity: MIDIVelocity,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        if channel == padChannel, handlePadNoteOff(note: noteNumber) {
            return
        } else {
            noteOff(noteNumber, channel: channel)
        }
    }

    func receivedMIDIController(
        _ controller: MIDIByte,
        value: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {
        handleControl(controller, value: value)
    }

    func receivedMIDIAftertouch(
        noteNumber: MIDINoteNumber,
        pressure: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    func receivedMIDIAftertouch(
        _ pressure: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    func receivedMIDIPitchWheel(
        _ pitchWheelValue: MIDIWord,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    func receivedMIDIProgramChange(
        _ program: MIDIByte,
        channel: MIDIChannel,
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    func receivedMIDISystemCommand(
        _ data: [MIDIByte],
        portID: MIDIUniqueID?,
        timeStamp: MIDITimeStamp?
    ) {}

    func receivedMIDISetupChange() {}

    func receivedMIDIPropertyChange(propertyChangeInfo: MIDIObjectPropertyChangeNotification) {}

    func receivedMIDINotification(notification: MIDINotification) {}
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
