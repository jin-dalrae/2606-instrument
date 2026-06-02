import SwiftUI

struct ScrollingScoreView: View {
    @EnvironmentObject private var audio: AudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PLAYED NOTE SCORE")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.leading, 10)
            
            ScrollingScoreCanvas(notes: audio.scoreNotes)
                .frame(height: 130)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

struct ScrollingScoreCanvas: View {
    let notes: [ScoreNote]
    
    // Speed: points per second
    private let speed: CGFloat = 50.0
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = Date()
                drawGrid(in: &context, size: size)
                drawNotes(in: &context, size: size, now: now)
            }
        }
    }
    
    private func diatonicIndex(for midiNote: UInt8) -> Int {
        let pitchClass = Int(midiNote % 12)
        let octave = Int(midiNote / 12) - 5
        let offsets = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        return octave * 7 + offsets[pitchClass]
    }
    
    private func yCoordinate(for midiNote: UInt8, centerY: CGFloat) -> CGFloat {
        // Spacing between lines of staff: index offset * 3.8 points
        let index = diatonicIndex(for: midiNote) - diatonicIndex(for: 60)
        return centerY - CGFloat(index) * 3.8
    }
    
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height * 0.5
        let staffColor = Color.white.opacity(0.16)
        
        // Draw Treble lines (indices 2, 4, 6, 8, 10)
        for index in [2, 4, 6, 8, 10] {
            let y = centerY - CGFloat(index) * 3.8
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(staffColor), style: StrokeStyle(lineWidth: 1))
        }
        
        // Draw Bass lines (indices -10, -8, -6, -4, -2)
        for index in [-10, -8, -6, -4, -2] {
            let y = centerY - CGFloat(index) * 3.8
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(staffColor), style: StrokeStyle(lineWidth: 1))
        }
        
        // Draw clefs
        let font = Font.system(size: 24, weight: .regular)
        context.draw(Text("𝄞").font(font).foregroundColor(.white.opacity(0.35)), at: CGPoint(x: 22, y: centerY - 24))
        context.draw(Text("𝄢").font(font).foregroundColor(.white.opacity(0.35)), at: CGPoint(x: 22, y: centerY + 24))
        
        // Draw playhead vertical line at the right side of the screen
        let playheadX = size.width - 60.0
        var pPath = Path()
        pPath.move(to: CGPoint(x: playheadX, y: 10))
        pPath.addLine(to: CGPoint(x: playheadX, y: size.height - 10))
        context.stroke(pPath, with: .color(Color.red.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
    }
    
    private func drawNotes(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let centerY = size.height * 0.5
        let playheadX = size.width - 60.0
        
        let layerColors: [Color] = [
            Color.green,  // Layer 1
            Color.cyan,   // Layer 2
            Color.pink,   // Layer 3
            Color.purple  // Layer 4
        ]
        
        for note in notes {
            let age = now.timeIntervalSince(note.startTime)
            let xStart = playheadX - CGFloat(age) * speed
            
            let xEnd: CGFloat
            let isActive: Bool
            if let endTime = note.endTime {
                let endAge = now.timeIntervalSince(endTime)
                xEnd = playheadX - CGFloat(endAge) * speed
                isActive = false
            } else {
                xEnd = playheadX
                isActive = true
            }
            
            // Skip if out of screen bounds (completely scrolled off the left edge)
            if xEnd < 0 {
                continue
            }
            
            let y = yCoordinate(for: note.pitch, centerY: centerY)
            let color = layerColors[note.layer % layerColors.count]
            
            // Draw Middle C ledger line if pitch matches 60 (index 0)
            if note.pitch == 60 {
                var ledg = Path()
                ledg.move(to: CGPoint(x: xStart - 6, y: y))
                ledg.addLine(to: CGPoint(x: xStart + 6, y: y))
                context.stroke(ledg, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1))
            }
            
            // Draw note tail
            var tailPath = Path()
            tailPath.move(to: CGPoint(x: xStart, y: y))
            tailPath.addLine(to: CGPoint(x: xEnd, y: y))
            context.stroke(tailPath, with: .color(color.opacity(isActive ? 0.8 : 0.45)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // Draw note head
            let noteHeadRect = CGRect(x: xStart - 3.5, y: y - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: noteHeadRect), with: .color(color))
            
            // Active glow (rendered at the playhead line where triggering occurs)
            if isActive {
                let glowRect = CGRect(x: playheadX - 5.5, y: y - 5.5, width: 11, height: 11)
                context.stroke(Path(ellipseIn: glowRect), with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1))
            }
        }
    }
}
