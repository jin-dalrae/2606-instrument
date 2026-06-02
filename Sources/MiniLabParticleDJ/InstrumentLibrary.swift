import Foundation

struct InstrumentPreset: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let program: UInt8
    let bankMSB: UInt8
    let bankLSB: UInt8

    static let melodicBankMSB: UInt8 = 0x79
    static let percussionBankMSB: UInt8 = 0x78

    static let starterPresets: [InstrumentPreset] = [
        .init(id: 0, name: "Grand Piano", program: 0, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 1, name: "EP Stage", program: 4, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 2, name: "Clav", program: 7, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 3, name: "Drawbar", program: 16, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 4, name: "Nylon Guitar", program: 24, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 5, name: "Picked Bass", program: 34, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 6, name: "Warm Pad", program: 89, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 7, name: "Poly Synth", program: 90, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 8, name: "Square Lead", program: 80, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 9, name: "Saw Lead", program: 81, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 10, name: "Choir", program: 52, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 11, name: "Strings", program: 48, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 12, name: "Brass", program: 61, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 13, name: "Flute", program: 73, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 14, name: "Pluck", program: 45, bankMSB: melodicBankMSB, bankLSB: 0),
        .init(id: 15, name: "Drum Kit", program: 0, bankMSB: percussionBankMSB, bankLSB: 0)
    ]
}

struct TimeSignatureOption: Identifiable, Hashable, Codable {
    let beats: Int
    let beatUnit: Int

    var id: String {
        label
    }

    var label: String {
        "\(beats)/\(beatUnit)"
    }

    var measureBeatsInQuarterNotes: Double {
        Double(beats) * (4 / Double(beatUnit))
    }

    static let options: [TimeSignatureOption] = [
        .init(beats: 4, beatUnit: 4),
        .init(beats: 3, beatUnit: 4),
        .init(beats: 6, beatUnit: 8),
        .init(beats: 3, beatUnit: 8)
    ]
}

enum StarterSoundBank {
    static let systemDLSURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
}

struct PersistableLayerState: Codable {
    let id: Int
    let name: String
    let presetID: Int?
    let customInstrumentBookmarkData: Data?
    let customInstrumentFilename: String?
    let volume: Double
    let isMuted: Bool
    let isSoloed: Bool
    let octaveOffset: Int
    var delayFeedback: Double? = 0.3
    var delayTime: Double? = 0.35
    var delayDryWet: Double? = 0.0
    var reverbDryWet: Double? = 0.0
}

enum VisualScene: String, Codable, CaseIterable, Identifiable {
    case hyperdrive = "Hyperdrive"
    case rain = "Rain"
    case orbit = "Orbit"
    case nebula = "Nebula"

    var id: String { self.rawValue }
}

struct SessionState: Codable {
    let tempoBPM: Double
    let selectedTimeSignatureIndex: Int
    let loopEnabled: Bool
    let drumEnabled: Bool
    let harmonyComplexity: Double
    let keyRootIndex: Int
    let keyModeRawValue: String
    let padChannelNumber: Int
    let currentLayer: Int
    var activeScene: VisualScene? = .hyperdrive
    let layers: [PersistableLayerState]
}

struct ImportedSoundFont: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let name: String
    let bookmarkData: Data
}

enum ControlTarget: String, Codable, CaseIterable, Identifiable {
    case brightness = "Brightness"
    case gravity = "Gravity"
    case particleSize = "Particle Size / Spread"
    case trail = "Trail / Voices"

    var id: String { self.rawValue }
}

struct MIDIMappingConfiguration: Codable, Equatable {
    var ccMappings: [Int: ControlTarget]
    var padMappings: [Int: Int]

    static let `default` = MIDIMappingConfiguration(
        ccMappings: [
            74: .brightness,
            71: .gravity,
            73: .particleSize,
            72: .trail
        ],
        padMappings: (0..<16).reduce(into: [Int: Int]()) { dict, index in
            dict[36 + index] = index
        }
    )
}

enum LearnSlot: Codable, Equatable, Hashable {
    case cc(ControlTarget)
    case pad(Int)
}

struct ScoreNote: Identifiable, Codable {
    let id: UUID
    let pitch: UInt8
    let startTime: Date
    var endTime: Date?
    let layer: Int
    
    init(id: UUID = UUID(), pitch: UInt8, startTime: Date, endTime: Date? = nil, layer: Int) {
        self.id = id
        self.pitch = pitch
        self.startTime = startTime
        self.endTime = endTime
        self.layer = layer
    }
}

