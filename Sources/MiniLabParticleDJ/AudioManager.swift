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
}

struct PerformanceControls {
    var brightness: Double = 0.76
    var gravity: Double = 0.42
    var particleSize: Double = 0.54
    var trail: Double = 0.68
}

final class AudioManager: ObservableObject {
    let padBaseNote: MIDINoteNumber = 36

    @Published var currentLayer = 0
    @Published var layers: [LayerState]
    @Published var visualizerBands = VisualizerBands()
    @Published var controls = PerformanceControls()
    @Published var scaleLabel = "C Major"
    @Published var status = "Audio engine idle"
    @Published var lastMIDIEvent = "Waiting for MiniLab Mk2"
    @Published var lastPadIndex: Int?

    private let engine = AudioEngine()
    private let mixer = Mixer()
    private let midi = MIDI()
    private let harmony = HarmonyEngine()
    private var samplers: [AppleSampler] = []
    private var fftTap: FFTTap?
    private var loadedCustomInstrumentURLs: [Int: URL] = [:]

    init() {
        let presets = InstrumentPreset.starterPresets
        layers = (0..<4).map { index in
            LayerState(id: index, name: "Layer \(index + 1)", preset: presets[index])
        }

        for _ in 0..<4 {
            let sampler = AppleSampler()
            samplers.append(sampler)
            mixer.addInput(sampler)
        }

        engine.output = mixer
        midi.addListener(self)
    }

    func start() {
        do {
            try engine.start()
            midi.openInput()
            configureFFT()
            loadStarterPresets()
            publishStatus("Engine running. Listening to Core MIDI inputs.")
        } catch {
            publishStatus("Engine failed: \(error.localizedDescription)")
        }
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
        }
    }

    private func noteOn(_ note: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        guard samplers.indices.contains(currentLayer) else { return }

        samplers[currentLayer].play(noteNumber: note, velocity: velocity, channel: channel)

        let activeNotes = layers.flatMap(\.activeNotes)
        let snapshot = harmony.snapshot(activeNotes: Set(activeNotes), fallbackNote: note)
        let harmonyNotes = harmony.harmonyNotes(for: note, snapshot: snapshot)
        let harmonyVelocity = MIDIVelocity((Double(velocity) * 0.68).rounded().clamped(to: 1...127))

        for (offset, harmonyNote) in harmonyNotes.enumerated() {
            let layer = (currentLayer + offset + 1) % samplers.count
            samplers[layer].play(noteNumber: harmonyNote, velocity: harmonyVelocity, channel: channel)
        }

        DispatchQueue.main.async {
            self.layers[self.currentLayer].activeNotes.insert(note)
            self.scaleLabel = snapshot.label
            self.visualizerBands.lastVelocity = (Double(velocity) / 127).clamped(to: 0...1)
            self.lastMIDIEvent = "Note \(note) velocity \(velocity)"
        }
    }

    private func noteOff(_ note: MIDINoteNumber, channel: MIDIChannel) {
        for sampler in samplers {
            sampler.stop(noteNumber: note, channel: channel)
        }

        let snapshot = harmony.snapshot(activeNotes: Set(layers.flatMap(\.activeNotes)), fallbackNote: note)
        for harmonyNote in harmony.harmonyNotes(for: note, snapshot: snapshot) {
            for sampler in samplers {
                sampler.stop(noteNumber: harmonyNote, channel: channel)
            }
        }

        DispatchQueue.main.async {
            for layer in self.layers.indices {
                self.layers[layer].activeNotes.remove(note)
            }
            self.lastMIDIEvent = "Note off \(note)"
        }
    }

    private func handlePad(note: MIDINoteNumber) -> Bool {
        guard note >= padBaseNote else { return false }
        let padIndex = Int(note - padBaseNote)
        guard InstrumentPreset.starterPresets.indices.contains(padIndex) else { return false }

        let preset = InstrumentPreset.starterPresets[padIndex]
        loadPreset(preset, into: currentLayer)
        DispatchQueue.main.async {
            self.lastPadIndex = padIndex
            self.lastMIDIEvent = "Pad \(padIndex + 1): \(preset.name)"
        }
        return true
    }

    private func handleControl(_ controller: MIDIByte, value: MIDIByte) {
        let normalized = Double(value) / 127

        DispatchQueue.main.async {
            switch controller {
            case 74:
                self.controls.brightness = normalized
            case 71:
                self.controls.gravity = normalized
            case 73:
                self.controls.particleSize = normalized
            case 72:
                self.controls.trail = normalized
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

        if !handlePad(note: noteNumber) {
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
        noteOff(noteNumber, channel: channel)
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
