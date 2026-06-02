import SwiftUI

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var hue: Double
    var life: Double
    var size: Double
}

struct ParticleVisualizer: View {
    let bands: VisualizerBands
    let controls: PerformanceControls

    @State private var particles: [Particle] = []
    @State private var lastUpdate = Date()
    @State private var lastTriggerID = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                updateParticles(at: timeline.date, size: size)
                drawBackground(in: &context, size: size)
                drawParticles(in: &context)
                drawSpectrum(in: &context, size: size)
            }
        }
        .background(Color.black)
    }

    private func updateParticles(at date: Date, size: CGSize) {
        let delta = min(1 / 20, max(1 / 120, date.timeIntervalSince(lastUpdate)))
        lastUpdate = date

        let gravity = (controls.gravity - 0.5) * 90
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
        let energy = max(bands.amplitude, bands.lastVelocity * 0.8)
        let triggerBurst = bands.triggerID != lastTriggerID
        if triggerBurst {
            lastTriggerID = bands.triggerID
        }

        let spawnCount = Int((18 + energy * 52 + bands.bass * 72 + (triggerBurst ? 140 : 0)).clamped(to: 12...220))

        for _ in 0..<spawnCount {
            let angle = Double.random(in: 0..<(Double.pi * 2))
            let speed = Double.random(in: 42...260) * (0.45 + energy)
            let hue = (0.55 + bands.mid * 0.22 + bands.treble * 0.18 + Double.random(in: -0.04...0.04)).truncatingRemainder(dividingBy: 1)
            particles.append(
                Particle(
                    position: center.jittered(radius: 20 + bands.bass * 80),
                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                    hue: hue,
                    life: Double.random(in: 0.55...1.45),
                    size: Double.random(in: 1.5...7.0) * (0.65 + controls.particleSize * 1.7)
                )
            )
        }

        let decay = 0.78 + controls.trail * 0.18
        for index in particles.indices {
            particles[index].velocity.dx *= decay
            particles[index].velocity.dy = particles[index].velocity.dy * decay + gravity * delta
            particles[index].position.x += particles[index].velocity.dx * delta
            particles[index].position.y += particles[index].velocity.dy * delta
            particles[index].life -= delta * (0.58 + bands.treble * 0.65)
        }

        particles.removeAll { particle in
            particle.life <= 0 ||
            particle.position.x < -80 ||
            particle.position.x > size.width + 80 ||
            particle.position.y < -80 ||
            particle.position.y > size.height + 80
        }

        if particles.count > 12_000 {
            particles.removeFirst(particles.count - 12_000)
        }
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(Color(red: 0.015, green: 0.018, blue: 0.026)))

        let pulse = bands.bass * 0.22 + bands.mid * 0.12
        let radial = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [
                Color(hue: 0.58 + bands.treble * 0.12, saturation: 0.68, brightness: 0.18 + controls.brightness * pulse),
                Color(red: 0.005, green: 0.007, blue: 0.012)
            ]),
            center: CGPoint(x: size.width * 0.5, y: size.height * 0.52),
            startRadius: 40,
            endRadius: max(size.width, size.height) * 0.75
        )
        context.fill(Path(rect), with: radial)
    }

    private func drawParticles(in context: inout GraphicsContext) {
        if particles.isEmpty {
            return
        }

        for particle in particles {
            let alpha = particle.life.clamped(to: 0...1)
            let rect = CGRect(
                x: particle.position.x - particle.size * 0.5,
                y: particle.position.y - particle.size * 0.5,
                width: particle.size,
                height: particle.size
            )
            let color = Color(hue: particle.hue, saturation: 0.88, brightness: 0.72 + controls.brightness * 0.28)
                .opacity(alpha)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func drawSpectrum(in context: inout GraphicsContext, size: CGSize) {
        let values = [bands.bass, bands.mid, bands.treble]
        let colors = [
            Color(red: 0.12, green: 0.72, blue: 1.0),
            Color(red: 0.56, green: 0.92, blue: 0.42),
            Color(red: 1.0, green: 0.38, blue: 0.66)
        ]
        let width = size.width * 0.16
        let startX = size.width * 0.5 - width * 1.65
        let y = size.height - 46

        for index in values.indices {
            let barHeight = 8 + values[index] * 58
            let rect = CGRect(x: startX + CGFloat(index) * width * 1.1, y: y - barHeight, width: width, height: barHeight)
            let path = RoundedRectangle(cornerRadius: 4).path(in: rect)
            context.fill(path, with: .color(colors[index].opacity(0.72)))
        }
    }
}

private extension CGPoint {
    func jittered(radius: Double) -> CGPoint {
        let angle = Double.random(in: 0..<(Double.pi * 2))
        let distance = Double.random(in: 0...radius)
        return CGPoint(x: x + cos(angle) * distance, y: y + sin(angle) * distance)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
