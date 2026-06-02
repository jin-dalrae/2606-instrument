import Foundation

struct InstrumentPreset: Identifiable, Hashable {
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

struct TimeSignatureOption: Identifiable, Hashable {
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
