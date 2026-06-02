# MiniLab Particle DJ

MiniLab Particle DJ is a native macOS performance app for turning an Arturia MiniLab Mk2 into a compact synth, DJ, and VJ station. It combines low-latency local MIDI input, layered AudioKit samplers, automatic harmony, pad-based instrument switching, smart on-screen chord pads, a real-time scrolling note score, and a reactive particle visualizer in one SwiftUI app.

The app is designed for a Mac Mini or MacBook running fully on-device. No cloud services are required for MIDI, audio generation, harmony, or visuals.

## Current Features

- **Visualizer-First Glassmorphism**: Premium macOS `.ultraThinMaterial` styling with scrollable container safety to prevent UI truncation on smaller monitors (at least `1120 x 720`).
- **Smart On-Screen Chord Pads**: Eight diatonic chord pads adapt to the active key and scale. Clicking a pad triggers a quantized one-shot note with auto-release, so you can fire harmonic ideas without holding the mouse down.
- **Zero-Routing Audio**: Integrated AudioKit 5 audio graph with one `AudioEngine`, four `AppleSampler` layers, and a shared output `Mixer` running on-device without needing external DAWs or loopback drivers.
- **Core MIDI Input**: Direct MIDI input handling with an active device monitor panel listing connected interfaces.
- **Arturia MiniLab Mk2 Mappings**:
  - Keys play the selected layer and trigger automatic backing harmonies.
  - Pads select performance instruments or acts as layer/harmony-mode modifiers.
  - Knobs modulate visualizer parameters (brightness, gravity, particle size, trails).
- **Auto-Harmony Engine**: Rules-based engine that detects key/chord context and plays diatonic accompaniment voices arpeggiated across other layers.
- **Real-Time Scrolling Note Score**: A scrolling grand staff displaying treble/bass clefs, Middle C ledger lines, color-coded layer note tracks, and active glows, synchronized with zero visual latency (playhead at `size.width - 60`).
- **Performance Looper & Companion**: Captures played phrases and loops them up to five times with a gradual volume decay. Includes a step drum beat companion aligned to BPM and Time Signature. Looped phrases preserve the instrument that was captured with them.
- **Instruments Preset Selection Panel**: Dropdown menus to select and load instruments for each layer directly on the screen.
- **MIDI Learning Dashboard**: Remap any physical knob (CC) or pad (Note) directly from the visual settings tab. Mappings automatically persist in `UserDefaults`.

## Requirements

- macOS 14 or newer.
- Xcode with Swift Package Manager support.
- Arturia MiniLab Mk2 or another Core MIDI controller.
- Optional `.sf2` or `.dls` instrument libraries.

## Setup

1. Connect your MIDI controller via USB.
2. Open the Swift package in Xcode:
   ```sh
   open Package.swift
   ```
3. Select the `MiniLabParticleDJ` scheme.
4. Choose `My Mac` as the run destination.
5. Run the app (`Cmd + R`).

## Competitive Analysis

How **MiniLab Particle DJ** compares to alternative VJ and MIDI performance solutions:

| App / Project | Category | Strengths | Weaknesses / Gaps | MiniLab Particle DJ Advantage |
| :--- | :--- | :--- | :--- | :--- |
| **Vythm VJ / Euler VS / Imaginando VS** | Visual Synthesizers (App Store) | High-end 3D graphics, particle systems, shader presets. | **No audio generation**. Requires running a separate DAW + setting up virtual loopback drivers (e.g. Loopback, IAC) which increases latency and CPU overhead. | **All-in-One Integration**: Bundles zero-latency AudioKit samplers, MIDI learning, auto-harmony, drum sequencers, and reactive visuals into *one single app* with no routing required. |
| **Apple MainStage / Gig Performer** | Audio Host Rig | Professional audio effects, routing, and VST/AU hosting. | **No built-in visuals**. Requires routing MIDI/audio out to a separate VJ app. Heavy resource footprint and steep learning curve. | **VJ-First Design**: Visually stunning particle system is built-in and mapped directly to music theory events (pitch, velocity, harmony) natively. |
| **SeeMusic / MIDITrail** | 3D Piano Renderers | Beautiful 3D falling-note visualizers. | Designed as file players or visual recorders, not live performance rigs. **No audio engines**. | **Interactive Performance**: Designed specifically for live hardware triggers, loop capturing, and custom MIDI remapping. |
| **MIDIVisualizer (kosua20)** | Open Source (GitHub) | Lightweight, OpenGL-based piano roll and particle generator. | **No audio synthesis**. Purely visual utility. | **Sound & Harmony**: Integrates an active synthesizer, auto-harmony engine, and physical drumbeat out-of-the-box. |

## MIDI Mapping

The default mapping is configured in `AudioManager.swift` and can be customized via the MIDI Settings UI.

| Control | MIDI | Behavior |
| --- | --- | --- |
| Keyboard | Note on/off | Plays current layer and triggers auto-harmony on other layers |
| On-screen chord pads | Mouse click | Fires quantized one-shot chord tones with auto-release |
| Pads | Notes `36...51` | Select instrument presets (Pads 1-16) |
| Pads (Modifier) | Hold Pad 13 + Pads 1-4 | Select active synthesizer layer (1-4) |
| Pads (Modifier) | Hold Pad 13 + Pad 15 | Toggle phrase loop playback (ON/OFF) |
| Pads (Modifier) | Hold Pad 13 + Pad 16 | Toggle companion drumbeat (ON/OFF) |
| Pads (Modifier) | Hold Pad 14 + Pads 1-7 | Select harmony mode (Off, Close 3rds, Open 5ths, Triad, Dreamy, Seventh, Octaves) |
| Pads (Modifier) | Hold Pad 1 + Pad 16 | Panic / stop all active notes and schedulers |
| Knob | CC `74` | Visual brightness |
| Knob | CC `71` | Visual gravity |
| Knob | CC `73` | Visual particle size + harmony spread |
| Knob | CC `72` | Visual trail length + harmony voice count |
| MIDI | CC `120` or `123` | Panic / all notes off |

## Looping

The upper settings panel is grouped by purpose:

- `Playback`: Loop on/off and Drums on/off.
- `Rhythm`: Tempo in BPM and time signature.
- `Key`: Root note plus major or minor scale.
- `Harmony`: Complexity, which controls arpeggiator density and micro-timing arpeggiations.
- `MIDI`: Stepper for pad channel.

When you play, the app captures the melody plus its generated harmony voices as a phrase. At the next measure, it repeats that phrase five times, fading away gradually. On-screen chord pads fire quantized one-shot notes, so a single click is enough to launch the harmonic figure.

## Instruments

The starter presets use the macOS system DLS bank:
```text
/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls
```

To load custom SoundFonts, click on a layer's preset selector dropdown, select **Import SoundFont / DLS...**, and choose a file. Bookmarks are automatically generated and persist in `UserDefaults` so files reload on relaunch.

## Project Structure

```text
Package.swift
README.md
docs/PRD.md
docs/UserManual.md
Sources/MiniLabParticleDJ/
  AudioManager.swift          Audio engine, samplers, MIDI, FFT, layer state
  ContentView.swift           Main SwiftUI performance UI
  HarmonyEngine.swift         Scale detection and harmony note generation
  InstrumentLibrary.swift     Starter DLS preset list and mapping models
  MiniLabParticleDJApp.swift  App entry point
  ParticleVisualizer.swift    Canvas particle renderer
  ScrollingScoreView.swift    Real-time scrolling grand staff canvas
  Resources/SoundFonts/       Optional bundled instruments
```

## Development

Validate the package from the terminal:

```sh
swift build
```

This project is configured with strict Swift 6 concurrency checking (`swiftLanguageModes: [.v6]` in `Package.swift`). All mutable audio and UI state is isolated to `@MainActor` in `AudioManager.swift`, and incoming CoreMIDI background callbacks are safely routed across actor boundaries using modern Swift concurrency constructs.

## Roadmap

See [docs/PRD.md](docs/PRD.md) for the product requirements, current scope, and completed milestones.
