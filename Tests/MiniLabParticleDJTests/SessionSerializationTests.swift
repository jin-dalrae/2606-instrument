import XCTest
@testable import MiniLabParticleDJ

final class SessionSerializationTests: XCTestCase {
    
    func testSessionStateEncodingDecoding() throws {
        // Arrange: Create a sample PersistableLayerState
        let layer1 = PersistableLayerState(
            id: 0,
            name: "Grand Piano",
            presetID: 0,
            customInstrumentBookmarkData: nil,
            customInstrumentFilename: nil,
            volume: 0.85,
            isMuted: false,
            isSoloed: false,
            octaveOffset: 1,
            delayFeedback: 0.45,
            delayTime: 0.25,
            delayDryWet: 0.15,
            reverbDryWet: 0.35
        )
        
        let layer2 = PersistableLayerState(
            id: 1,
            name: "Custom SoundFont",
            presetID: nil,
            customInstrumentBookmarkData: Data([1, 2, 3, 4]),
            customInstrumentFilename: "my_synth.sf2",
            volume: 0.90,
            isMuted: true,
            isSoloed: false,
            octaveOffset: -1,
            delayFeedback: 0.5,
            delayTime: 0.4,
            delayDryWet: 0.0,
            reverbDryWet: 0.6
        )
        
        let session = SessionState(
            tempoBPM: 120.0,
            selectedTimeSignatureIndex: 1,
            loopEnabled: true,
            drumEnabled: false,
            harmonyComplexity: 0.75,
            keyRootIndex: 3,
            keyModeRawValue: "Minor",
            padChannelNumber: 10,
            currentLayer: 0,
            activeScene: .orbit,
            layers: [layer1, layer2]
        )
        
        // Act: Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        // Assert: Decode and check equality
        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(SessionState.self, from: data)
        
        XCTAssertEqual(decodedSession.tempoBPM, session.tempoBPM)
        XCTAssertEqual(decodedSession.selectedTimeSignatureIndex, session.selectedTimeSignatureIndex)
        XCTAssertEqual(decodedSession.loopEnabled, session.loopEnabled)
        XCTAssertEqual(decodedSession.drumEnabled, session.drumEnabled)
        XCTAssertEqual(decodedSession.harmonyComplexity, session.harmonyComplexity)
        XCTAssertEqual(decodedSession.keyRootIndex, session.keyRootIndex)
        XCTAssertEqual(decodedSession.keyModeRawValue, session.keyModeRawValue)
        XCTAssertEqual(decodedSession.padChannelNumber, session.padChannelNumber)
        XCTAssertEqual(decodedSession.currentLayer, session.currentLayer)
        XCTAssertEqual(decodedSession.activeScene, session.activeScene)
        
        XCTAssertEqual(decodedSession.layers.count, session.layers.count)
        
        let decodedL1 = decodedSession.layers[0]
        XCTAssertEqual(decodedL1.id, layer1.id)
        XCTAssertEqual(decodedL1.name, layer1.name)
        XCTAssertEqual(decodedL1.presetID, layer1.presetID)
        XCTAssertNil(decodedL1.customInstrumentBookmarkData)
        XCTAssertEqual(decodedL1.volume, layer1.volume)
        XCTAssertEqual(decodedL1.isMuted, layer1.isMuted)
        XCTAssertEqual(decodedL1.isSoloed, layer1.isSoloed)
        XCTAssertEqual(decodedL1.octaveOffset, layer1.octaveOffset)
        XCTAssertEqual(decodedL1.delayFeedback, layer1.delayFeedback)
        XCTAssertEqual(decodedL1.delayTime, layer1.delayTime)
        XCTAssertEqual(decodedL1.delayDryWet, layer1.delayDryWet)
        XCTAssertEqual(decodedL1.reverbDryWet, layer1.reverbDryWet)
        
        let decodedL2 = decodedSession.layers[1]
        XCTAssertEqual(decodedL2.id, layer2.id)
        XCTAssertEqual(decodedL2.name, layer2.name)
        XCTAssertNil(decodedL2.presetID)
        XCTAssertEqual(decodedL2.customInstrumentBookmarkData, layer2.customInstrumentBookmarkData)
        XCTAssertEqual(decodedL2.customInstrumentFilename, layer2.customInstrumentFilename)
        XCTAssertEqual(decodedL2.volume, layer2.volume)
        XCTAssertEqual(decodedL2.isMuted, layer2.isMuted)
        XCTAssertEqual(decodedL2.isSoloed, layer2.isSoloed)
        XCTAssertEqual(decodedL2.octaveOffset, layer2.octaveOffset)
        XCTAssertEqual(decodedL2.delayFeedback, layer2.delayFeedback)
        XCTAssertEqual(decodedL2.delayTime, layer2.delayTime)
        XCTAssertEqual(decodedL2.delayDryWet, layer2.delayDryWet)
        XCTAssertEqual(decodedL2.reverbDryWet, layer2.reverbDryWet)
    }
}
