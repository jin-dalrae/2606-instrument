import AudioKit
import Foundation

enum HarmonyStyle: Int, CaseIterable {
    case off
    case closeThirds
    case openFifths
    case fullTriad
    case dreamy

    var name: String {
        switch self {
        case .off:
            "Off"
        case .closeThirds:
            "Close 3rds"
        case .openFifths:
            "Open 5ths"
        case .fullTriad:
            "Full Triad"
        case .dreamy:
            "Dreamy"
        }
    }
}

struct HarmonySettings {
    var style: HarmonyStyle = .closeThirds
    var lockedKey: HarmonyEngine.KeySignature?
    var maxVoices: Int = 2
    var spread: Int = 1
    var velocityScale: Double = 0.72
    var autocorrectMelody = false
}

struct HarmonyResult {
    let notes: [MIDINoteNumber]
    let snapshot: HarmonyEngine.Snapshot
}

struct HarmonyEngine {
    enum ScaleMode: String, CaseIterable {
        case major = "Major"
        case minor = "Minor"
        case pentatonic = "Pentatonic"
    }

    struct KeySignature: Equatable {
        var rootPitchClass: Int
        var mode: ScaleMode

        var label: String {
            "\(Self.pitchNames[rootPitchClass]) \(mode.rawValue)"
        }

        static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    }

    struct Chord: Equatable {
        enum Quality: String {
            case major = "maj"
            case minor = "min"
            case diminished = "dim"
            case suspended = "sus"
            case unknown = ""
        }

        var rootPitchClass: Int
        var quality: Quality

        var label: String {
            "\(KeySignature.pitchNames[rootPitchClass])\(quality.rawValue)"
        }
    }

    struct Snapshot {
        var key: KeySignature
        var chord: Chord?

        var keyLabel: String {
            key.label
        }

        var chordLabel: String {
            chord?.label ?? "No Chord"
        }

        var displayLabel: String {
            "\(keyLabel)  \(chordLabel)"
        }
    }

    private let majorScale = [0, 2, 4, 5, 7, 9, 11]
    private let minorScale = [0, 2, 3, 5, 7, 8, 10]
    private let pentatonicScale = [0, 2, 4, 7, 9]

    func harmonize(
        melodyNote: MIDINoteNumber,
        activeNotes: Set<MIDINoteNumber>,
        recentNotes: [MIDINoteNumber],
        settings: HarmonySettings
    ) -> HarmonyResult {
        let snapshot = snapshot(activeNotes: activeNotes, recentNotes: recentNotes, fallbackNote: melodyNote, lockedKey: settings.lockedKey)
        guard settings.style != .off, settings.maxVoices > 0 else {
            return HarmonyResult(notes: [], snapshot: snapshot)
        }

        let anchorPitchClass = snapshot.chord?.rootPitchClass ?? snapshot.key.rootPitchClass
        let chordDegrees = chordScaleDegrees(for: snapshot.chord, in: snapshot.key)
        let melodyDegree = nearestScaleDegree(for: melodyNote, in: snapshot.key)
        let intervals = voicingIntervals(
            style: settings.style,
            melodyDegree: melodyDegree,
            chordDegrees: chordDegrees,
            scale: scaleIntervals(for: snapshot.key.mode),
            spread: settings.spread
        )

        var notes = intervals.compactMap { interval in
            clampedMIDINote(Int(melodyNote) + interval)
        }

        if settings.style == .dreamy, let lowSupport = nearestChordTone(
            below: melodyNote,
            anchorPitchClass: anchorPitchClass,
            key: snapshot.key,
            maxDistance: 16
        ) {
            notes.insert(lowSupport, at: 0)
        }

        notes = Array(notes.prefix(settings.maxVoices))
        return HarmonyResult(notes: dedupe(notes, excluding: melodyNote), snapshot: snapshot)
    }

    func snapshot(
        activeNotes: Set<MIDINoteNumber>,
        recentNotes: [MIDINoteNumber],
        fallbackNote: MIDINoteNumber,
        lockedKey: KeySignature? = nil
    ) -> Snapshot {
        let notes = Array(activeNotes) + recentNotes.suffix(8)
        let key = lockedKey ?? detectedKey(notes: notes.isEmpty ? [fallbackNote] : notes, fallbackNote: fallbackNote)
        let chord = detectedChord(notes: Array(activeNotes).isEmpty ? recentNotes.suffix(4).map { $0 } : Array(activeNotes), key: key)
        return Snapshot(key: key, chord: chord)
    }

    func correctedMelodyNote(_ note: MIDINoteNumber, settings: HarmonySettings, snapshot: Snapshot) -> MIDINoteNumber {
        guard settings.autocorrectMelody else { return note }
        let degree = nearestScaleDegree(for: note, in: snapshot.key)
        let scale = scaleIntervals(for: snapshot.key.mode)
        let originalPitch = Int(note) - snapshot.key.rootPitchClass
        let octave = floorDiv(originalPitch, scale.count == 7 ? 12 : 12)
        let corrected = snapshot.key.rootPitchClass + scale[degree.index] + octave * 12
        return clampedMIDINote(nearestOctaveMatch(candidate: corrected, original: Int(note))) ?? note
    }

    private func detectedKey(notes: [MIDINoteNumber], fallbackNote: MIDINoteNumber) -> KeySignature {
        let weightedPitchClasses = notes.enumerated().map { index, note in
            (pitchClass: Int(note % 12), weight: index >= max(0, notes.count - 4) ? 3 : 1)
        }

        var best = KeySignature(rootPitchClass: Int(fallbackNote % 12), mode: .major)
        var bestScore = Int.min

        for root in 0..<12 {
            for mode in [ScaleMode.major, .minor, .pentatonic] {
                let scale = Set(scaleIntervals(for: mode))
                var score = 0
                for weighted in weightedPitchClasses {
                    let relative = (weighted.pitchClass - root + 12) % 12
                    score += scale.contains(relative) ? 2 * weighted.weight : -2 * weighted.weight
                    if relative == 0 {
                        score += weighted.weight
                    }
                }

                if score > bestScore {
                    bestScore = score
                    best = KeySignature(rootPitchClass: root, mode: mode)
                }
            }
        }

        return best
    }

    private func detectedChord(notes: [MIDINoteNumber], key: KeySignature) -> Chord? {
        let pitchClasses = Set(notes.map { Int($0 % 12) })
        guard pitchClasses.count >= 2 else { return nil }

        let qualities: [(Chord.Quality, Set<Int>, Int)] = [
            (.major, [0, 4, 7], 5),
            (.minor, [0, 3, 7], 5),
            (.diminished, [0, 3, 6], 4),
            (.suspended, [0, 5, 7], 3)
        ]

        var bestChord: Chord?
        var bestScore = Int.min

        for root in 0..<12 {
            for quality in qualities {
                let chordPitches = Set(quality.1.map { ($0 + root) % 12 })
                let matches = pitchClasses.intersection(chordPitches).count
                let misses = pitchClasses.subtracting(chordPitches).count
                let rootBonus = pitchClasses.contains(root) ? 2 : 0
                let keyBonus = scaleIntervals(for: key.mode).contains((root - key.rootPitchClass + 12) % 12) ? 1 : 0
                let score = matches * quality.2 - misses * 2 + rootBonus + keyBonus

                if score > bestScore {
                    bestScore = score
                    bestChord = Chord(rootPitchClass: root, quality: quality.0)
                }
            }
        }

        return bestScore >= 4 ? bestChord : nil
    }

    private func chordScaleDegrees(for chord: Chord?, in key: KeySignature) -> [Int] {
        guard let chord else { return [0, 2, 4] }
        let scale = scaleIntervals(for: key.mode)
        let chordRelativeRoot = (chord.rootPitchClass - key.rootPitchClass + 12) % 12
        let rootDegree = scale.enumerated().min { left, right in
            abs(left.element - chordRelativeRoot) < abs(right.element - chordRelativeRoot)
        }?.offset ?? 0

        switch chord.quality {
        case .major, .minor, .diminished:
            return [rootDegree, rootDegree + 2, rootDegree + 4, rootDegree + 6]
        case .suspended:
            return [rootDegree, rootDegree + 3, rootDegree + 4, rootDegree + 6]
        case .unknown:
            return [rootDegree, rootDegree + 2, rootDegree + 4]
        }
    }

    private func voicingIntervals(
        style: HarmonyStyle,
        melodyDegree: (index: Int, octave: Int),
        chordDegrees: [Int],
        scale: [Int],
        spread: Int
    ) -> [Int] {
        switch style {
        case .off:
            return []
        case .closeThirds:
            return [
                interval(from: melodyDegree, degreeOffset: 2, scale: scale),
                interval(from: melodyDegree, degreeOffset: 4, scale: scale),
                interval(from: melodyDegree, degreeOffset: 6, scale: scale)
            ]
        case .openFifths:
            return [
                interval(from: melodyDegree, degreeOffset: 4, scale: scale),
                interval(from: melodyDegree, degreeOffset: 7 + max(0, spread - 1), scale: scale),
                interval(from: melodyDegree, degreeOffset: -3, scale: scale)
            ]
        case .fullTriad:
            let targetDegrees = chordDegrees.filter { $0 != melodyDegree.index }
            return targetDegrees.map { interval(from: melodyDegree, absoluteDegree: $0, scale: scale) }
        case .dreamy:
            return [
                interval(from: melodyDegree, degreeOffset: 2, scale: scale),
                interval(from: melodyDegree, degreeOffset: 4 + max(0, spread - 1), scale: scale),
                interval(from: melodyDegree, degreeOffset: 9, scale: scale)
            ]
        }
    }

    private func interval(from melodyDegree: (index: Int, octave: Int), degreeOffset: Int, scale: [Int]) -> Int {
        interval(from: melodyDegree, absoluteDegree: melodyDegree.index + degreeOffset, scale: scale)
    }

    private func interval(from melodyDegree: (index: Int, octave: Int), absoluteDegree: Int, scale: [Int]) -> Int {
        let melodySemitone = scale[wrappedDegree(melodyDegree.index, count: scale.count)] + melodyDegree.octave * 12
        let targetOctave = floorDiv(absoluteDegree, scale.count)
        let targetSemitone = scale[wrappedDegree(absoluteDegree, count: scale.count)] + targetOctave * 12
        return targetSemitone - melodySemitone
    }

    private func nearestScaleDegree(for note: MIDINoteNumber, in key: KeySignature) -> (index: Int, octave: Int) {
        let scale = scaleIntervals(for: key.mode)
        let relative = Int(note) - key.rootPitchClass
        let octave = floorDiv(relative, 12)
        let pitch = positiveMod(relative, 12)
        let index = scale.enumerated().min { left, right in
            abs(left.element - pitch) < abs(right.element - pitch)
        }?.offset ?? 0
        return (index, octave)
    }

    private func nearestChordTone(
        below note: MIDINoteNumber,
        anchorPitchClass: Int,
        key: KeySignature,
        maxDistance: Int
    ) -> MIDINoteNumber? {
        let chordPitchClasses = Set([0, 3, 4, 7, 10].map { positiveMod(anchorPitchClass + $0, 12) })
        for distance in 5...maxDistance {
            let candidate = Int(note) - distance
            if candidate >= 0, chordPitchClasses.contains(candidate % 12) {
                return MIDINoteNumber(candidate)
            }
        }
        return nil
    }

    private func scaleIntervals(for mode: ScaleMode) -> [Int] {
        switch mode {
        case .major:
            majorScale
        case .minor:
            minorScale
        case .pentatonic:
            pentatonicScale
        }
    }

    private func dedupe(_ notes: [MIDINoteNumber], excluding melodyNote: MIDINoteNumber) -> [MIDINoteNumber] {
        var seen = Set<MIDINoteNumber>([melodyNote])
        return notes.filter { note in
            guard !seen.contains(note) else { return false }
            seen.insert(note)
            return true
        }
    }

    private func clampedMIDINote(_ value: Int) -> MIDINoteNumber? {
        guard (0...127).contains(value) else { return nil }
        return MIDINoteNumber(value)
    }

    private func nearestOctaveMatch(candidate: Int, original: Int) -> Int {
        let options = [candidate - 24, candidate - 12, candidate, candidate + 12, candidate + 24]
        return options.min { abs($0 - original) < abs($1 - original) } ?? candidate
    }

    private func wrappedDegree(_ value: Int, count: Int) -> Int {
        positiveMod(value, count)
    }

    private func positiveMod(_ value: Int, _ divisor: Int) -> Int {
        ((value % divisor) + divisor) % divisor
    }

    private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }
}
