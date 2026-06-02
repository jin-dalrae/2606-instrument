import SwiftUI

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var hue: Double
    var life: Double
    var size: Double
}

class ParticleState {
    var particles: [Particle] = []
    var lastUpdate = Date()
    var lastTriggerID = 0

    func updateParticles(at date: Date, size: CGSize, bands: VisualizerBands, controls: PerformanceControls, activeScene: VisualScene) {
        let delta = min(1 / 20, max(1 / 120, date.timeIntervalSince(lastUpdate)))
        lastUpdate = date

        let gravity = (controls.gravity - 0.5) * 90
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
        let energy = max(bands.amplitude, bands.lastVelocity * 0.8)
        let triggerBurst = bands.triggerID != lastTriggerID
        if triggerBurst {
            lastTriggerID = bands.triggerID
        }

        var spawnCount = 0
        switch activeScene {
        case .hyperdrive:
            spawnCount = Int((18 + energy * 52 + bands.bass * 72 + (triggerBurst ? 140 : 0)).clamped(to: 12...220))
        case .rain:
            spawnCount = Int((10 + energy * 30 + bands.bass * 40 + (triggerBurst ? 60 : 0)).clamped(to: 6...120))
        case .orbit:
            spawnCount = Int((14 + energy * 40 + bands.bass * 60 + (triggerBurst ? 100 : 0)).clamped(to: 10...180))
        case .nebula:
            spawnCount = Int((4 + energy * 15 + bands.bass * 20 + (triggerBurst ? 30 : 0)).clamped(to: 2...50))
        }

        for _ in 0..<spawnCount {
            let hue = (0.55 + bands.mid * 0.22 + bands.treble * 0.18 + Double.random(in: -0.04...0.04)).truncatingRemainder(dividingBy: 1)
            let particleSizeVal = Double.random(in: 1.5...7.0) * (0.65 + controls.particleSize * 1.7)

            switch activeScene {
            case .hyperdrive:
                let angle = Double.random(in: 0..<(Double.pi * 2))
                let speed = Double.random(in: 80...400) * (0.5 + energy * 1.5)
                particles.append(
                    Particle(
                        position: center.jittered(radius: 10 + bands.bass * 50),
                        velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                        hue: hue,
                        life: Double.random(in: 0.4...1.2),
                        size: particleSizeVal
                    )
                )
            case .rain:
                let posX = Double.random(in: 0...size.width)
                let speedY = Double.random(in: 150...350) * (0.6 + energy)
                let speedX = Double.random(in: -20...20)
                particles.append(
                    Particle(
                        position: CGPoint(x: posX, y: 0),
                        velocity: CGVector(dx: speedX, dy: speedY),
                        hue: hue,
                        life: Double.random(in: 2.0...4.0),
                        size: particleSizeVal * 0.75
                    )
                )
            case .orbit:
                let radius = Double.random(in: 50...300) * (0.8 + bands.bass)
                let angle = Double.random(in: 0..<(Double.pi * 2))
                let posX = center.x + cos(angle) * radius
                let posY = center.y + sin(angle) * radius
                let speed = Double.random(in: 60...180) * (0.6 + energy)
                let dx = -sin(angle) * speed
                let dy = cos(angle) * speed
                particles.append(
                    Particle(
                        position: CGPoint(x: posX, y: posY),
                        velocity: CGVector(dx: dx, dy: dy),
                        hue: hue,
                        life: Double.random(in: 1.2...2.5),
                        size: particleSizeVal
                    )
                )
            case .nebula:
                let posX = Double.random(in: 0...size.width)
                let posY = Double.random(in: 0...size.height)
                let angle = Double.random(in: 0..<(Double.pi * 2))
                let speed = Double.random(in: 10...40) * (0.5 + energy)
                particles.append(
                    Particle(
                        position: CGPoint(x: posX, y: posY),
                        velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                        hue: hue,
                        life: Double.random(in: 2.5...5.5),
                        size: particleSizeVal * Double.random(in: 2.0...4.5)
                    )
                )
            }
        }

        let decay = 0.78 + controls.trail * 0.18
        for index in particles.indices {
            switch activeScene {
            case .hyperdrive:
                let hDecay = decay * 1.05
                particles[index].velocity.dx *= hDecay
                particles[index].velocity.dy = particles[index].velocity.dy * hDecay + gravity * delta
                particles[index].position.x += particles[index].velocity.dx * delta
                particles[index].position.y += particles[index].velocity.dy * delta
                particles[index].life -= delta * (0.68 + bands.treble * 0.8)
            case .rain:
                let rainGravity = gravity + 180.0
                particles[index].velocity.dy += rainGravity * delta
                particles[index].position.x += particles[index].velocity.dx * delta
                particles[index].position.y += particles[index].velocity.dy * delta
                particles[index].life -= delta * 0.4
            case .orbit:
                let dx = particles[index].position.x - center.x
                let dy = particles[index].position.y - center.y
                let dist = sqrt(dx*dx + dy*dy)
                if dist > 5 {
                    let force = 4000.0 / dist * (0.5 + controls.gravity)
                    particles[index].velocity.dx -= (dx / dist) * force * delta
                    particles[index].velocity.dy -= (dy / dist) * force * delta
                }
                particles[index].velocity.dx *= 0.98
                particles[index].velocity.dy *= 0.98
                particles[index].position.x += particles[index].velocity.dx * delta
                particles[index].position.y += particles[index].velocity.dy * delta
                particles[index].life -= delta * (0.5 + bands.treble * 0.4)
            case .nebula:
                particles[index].velocity.dx *= 0.99
                particles[index].velocity.dy *= 0.99
                particles[index].velocity.dx += Double.random(in: -5...5) * delta
                particles[index].velocity.dy += Double.random(in: -5...5) * delta
                particles[index].position.x += particles[index].velocity.dx * delta
                particles[index].position.y += particles[index].velocity.dy * delta
                particles[index].life -= delta * 0.25
            }
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
}

struct ParticleVisualizer: View {
    let bands: VisualizerBands
    let controls: PerformanceControls
    let activeScene: VisualScene

    @State private var state = ParticleState()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = Date()
                    state.updateParticles(at: now, size: size, bands: bands, controls: controls, activeScene: activeScene)
                    drawBackground(in: &context, size: size)
                    drawParticles(in: &context, state: state)
                }
            }
        }
        .background(Color.black)
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)

        switch activeScene {
        case .hyperdrive:
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

        case .rain:
            context.fill(Path(rect), with: .color(Color(red: 0.008, green: 0.012, blue: 0.020)))
            let pulse = bands.bass * 0.15
            let linear = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    Color(red: 0.02 + pulse, green: 0.03 + pulse, blue: 0.05 + pulse),
                    Color(red: 0.002, green: 0.003, blue: 0.005)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
            context.fill(Path(rect), with: linear)

        case .orbit:
            context.fill(Path(rect), with: .color(Color(red: 0.018, green: 0.012, blue: 0.024)))
            let pulse = bands.bass * 0.3 + bands.mid * 0.1
            let radial = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [
                    Color(hue: 0.82 + bands.treble * 0.08, saturation: 0.75, brightness: 0.15 + controls.brightness * pulse),
                    Color(red: 0.005, green: 0.002, blue: 0.008)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.52),
                startRadius: 20,
                endRadius: max(size.width, size.height) * 0.85
            )
            context.fill(Path(rect), with: radial)

        case .nebula:
            context.fill(Path(rect), with: .color(Color(red: 0.01, green: 0.008, blue: 0.018)))
            let pulse = bands.bass * 0.2
            
            let radial1 = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [
                    Color(red: 0.0, green: 0.08 + pulse, blue: 0.18 + pulse).opacity(0.4),
                    Color.clear
                ]),
                center: CGPoint(x: size.width * 0.25, y: size.height * 0.4),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.6
            )
            context.fill(Path(rect), with: radial1)

            let radial2 = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [
                    Color(red: 0.15 + pulse, green: 0.0, blue: 0.15 + pulse).opacity(0.35),
                    Color.clear
                ]),
                center: CGPoint(x: size.width * 0.75, y: size.height * 0.6),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.6
            )
            context.fill(Path(rect), with: radial2)
        }
    }

    private func drawParticles(in context: inout GraphicsContext, state: ParticleState) {
        if state.particles.isEmpty {
            return
        }

        for particle in state.particles {
            var alpha = particle.life.clamped(to: 0...1)
            if activeScene == .nebula {
                alpha = (particle.life / 3.5).clamped(to: 0...1) * 0.35
            }

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
