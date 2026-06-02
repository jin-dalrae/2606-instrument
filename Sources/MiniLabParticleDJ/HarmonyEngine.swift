import AudioKit
import Foundation

struct HarmonyEngine {
    enum ScaleMode: String {
        case major = "Major"
        case minor = "Minor"
    }

    struct Snapshot {
        var rootPitchClass: Int = 0
        var mode: ScaleMode = .major

        var label: String {
            "\(Self.pitchNames[rootPitchClass]) \(mode.rawValue)"
        }

        private static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    }

    private let majorScale = Set([0, 2, 4, 5, 7, 9, 11])
    private let minorScale = Set([0, 2, 3, 5, 7, 8, 10])

    func snapshot(activeNotes: Set<MIDINoteNumber>, fallbackNote: MIDINoteNumber) -> Snapshot {
        let notes = activeNotes.isEmpty ? [fallbackNote] : Array(activeNotes)
        var best = Snapshot(rootPitchClass: Int(fallbackNote % 12), mode: .major)
        var bestScore = Int.min

        for root in 0..<12 {
            for mode in [ScaleMode.major, .minor] {
                let scale = mode == .major ? majorScale : minorScale
                let score = notes.reduce(0) { partial, note in
                    let pitch = (Int(note) - root + 12) % 12
                    return partial + (scale.contains(pitch) ? 2 : -1)
                }

                if score > bestScore {
                    bestScore = score
                    best = Snapshot(rootPitchClass: root, mode: mode)
                }
            }
        }

        return best
    }

    func harmonyNotes(for note: MIDINoteNumber, snapshot: Snapshot, voiceCount: Int = 3) -> [MIDINoteNumber] {
        let scale = snapshot.mode == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        let notePitch = (Int(note) - snapshot.rootPitchClass + 120) % 12
        let nearestDegree = scale.enumerated().min { left, right in
            abs(left.element - notePitch) < abs(right.element - notePitch)
        }?.offset ?? 0

        let degreeOffsets = [2, 4, 6, 9]
        return degreeOffsets.prefix(voiceCount).compactMap { offset in
            let targetDegree = nearestDegree + offset
            let octaveShift = targetDegree / scale.count
            let pitchClass = scale[targetDegree % scale.count]
            let semitone = pitchClass - scale[nearestDegree] + (octaveShift * 12)
            return clampedMIDINote(Int(note) + semitone)
        }
    }

    private func clampedMIDINote(_ value: Int) -> MIDINoteNumber? {
        guard (0...127).contains(value) else { return nil }
        return MIDINoteNumber(value)
    }
}
