# MiniLab Particle DJ

MiniLab Particle DJ is a native macOS performance app for turning an Arturia MiniLab Mk2 into a compact synth, DJ, and VJ station. It combines low-latency local MIDI input, layered AudioKit samplers, automatic harmony, pad-based instrument switching, and a reactive particle visualizer in one SwiftUI app.

The app is designed for a Mac Mini or MacBook running fully on-device. No cloud services are required for MIDI, audio generation, harmony, or visuals.

## Current Features

- Native macOS SwiftUI app targeting macOS 14 or newer.
- AudioKit 5 audio graph with one `AudioEngine`, four `AppleSampler` layers, and a shared output `Mixer`.
- Core MIDI input through AudioKit `MIDI`.
- Arturia MiniLab Mk2-friendly mapping:
  - Keys play the selected layer.
  - Pads select the performance instrument used by the melody and harmony layers.
  - Knobs control visualizer behavior.
- Four performance layers for melody plus automatically generated harmony voices.
- Built-in starter instrument presets loaded from the macOS system DLS sound bank.
- Audio-layer support for `.sf2` and `.dls` instruments.
- Rules-based harmony engine that detects key/chord context and adds diatonic GarageBand-style harmony voices.
- FFT-driven SwiftUI `Canvas` particle visualizer with bass, mid, treble, note velocity, and knob modulation.
- Visualizer-first performance screen with a compact HUD and rhythm controls.
- Particle-only visualizer; graph-style meters are intentionally not drawn over the performance view.
- Echo looper that repeats played notes and harmonies five times, fading gradually on each repeat.
- Key, scale, time-signature, BPM, drum, and harmony-complexity controls.
- Basic drum rhythm plus a selectable Drum Kit instrument.
- Played-event log showing the note, instrument, harmony mode, and rhythm used for recent phrases.
- Measure-aware looping: repeats are quantized to the selected time signature instead of firing at arbitrary release times.

## Requirements

- macOS 14 or newer.
- Xcode with Swift Package Manager support.
- Arturia MiniLab Mk2 or another Core MIDI controller.
- Optional `.sf2` or `.dls` instrument libraries.

The package can be parsed and built from the command line, but running as a Mac app is best done from Xcode.

## Setup

Clone or open this repository, then open the Swift package in Xcode:

```sh
open Package.swift
```

In Xcode:

1. Select the `MiniLabParticleDJ` scheme.
2. Choose `My Mac` as the run destination.
3. Connect the MiniLab Mk2 over USB.
4. Run the app.

The first build will fetch AudioKit from GitHub.

## MIDI Mapping

The current mapping is intentionally simple and easy to change in `AudioManager.swift`.

| Control | MIDI | Behavior |
| --- | --- | --- |
| Keyboard | Note on/off | Plays the current sampler layer and triggers harmony on other layers |
| Pads on MIDI channel 10 | Notes `36...51` | Select one of 16 starter instrument presets for melody + harmony |
| Pads on MIDI channel 10 | Hold notes `36` + `51` | Panic / all notes off |
| Pads on MIDI channel 10 | Hold note `48` + pads `36...39` | Select layer 1-4 |
| Pads on MIDI channel 10 | Hold note `49` + pads `36...40` | Select harmony mode: off, close 3rds, open 5ths, full triad, dreamy |
| Knob | CC `74` | Visual brightness |
| Knob | CC `71` | Visual gravity |
| Knob | CC `73` | Visual particle size + harmony spread |
| Knob | CC `72` | Visual trail length + harmony voice count |
| MIDI | CC `120` or `123` | Panic / all notes off |

If your MiniLab pad notes differ, update `padBaseNote` in `Sources/MiniLabParticleDJ/AudioManager.swift`. If instruments do not change from the pads, set the MiniLab pads to MIDI channel 10 in Arturia MIDI Control Center or update `padChannel` in `AudioManager.swift`.

Keyboard notes in the `36...51` range are treated as music, not instrument selection, unless they arrive on the configured pad channel.

## Looping

The bottom rhythm control sets the loop timing:

- `Speed`: tempo in BPM.
- `Time`: time signature, currently `4/4`, `3/4`, `6/8`, or `3/8`.
- `Key`: root note such as C, C#, D, etc.
- `Scale`: major, minor, or pentatonic.
- `Complex`: harmony density and rhythmic movement.
- Repeat switch: enables or disables the echo looper.
- `Drums`: enables or disables the built-in beat.
- `Pad Ch`: MIDI channel used for MiniLab pad instrument changes.

When you play and release a note, the app loops the melody plus its generated harmony voices five times. Repeats are aligned to the next measure using the selected time signature and BPM. Each repeat is quieter than the previous one, so phrases fade away naturally instead of building forever.

Looped phrases keep the instrument they were recorded with. If you play a piano phrase, switch to strings, and play another phrase, the older piano loop stays piano.

## Instruments

The starter presets use the macOS system DLS bank:

```text
/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls
```

The current UI is intentionally performance-focused. SoundFont loading support exists in the audio layer, while the visible screen prioritizes MiniLab control, rhythm settings, and visual output.

For bundled SoundFont packs, place files under:

```text
Sources/MiniLabParticleDJ/Resources/SoundFonts
```

The app does not bundle third-party SoundFonts yet. Keep license files with any packs you add.

## Project Structure

```text
Package.swift
README.md
docs/PRD.md
Sources/MiniLabParticleDJ/
  AudioManager.swift          Audio engine, samplers, MIDI, FFT, layer state
  ContentView.swift           Main SwiftUI performance UI
  HarmonyEngine.swift         Scale detection and harmony note generation
  InstrumentLibrary.swift     Starter DLS preset list
  MiniLabParticleDJApp.swift  App entry point
  ParticleVisualizer.swift    Canvas particle renderer
  Resources/SoundFonts/       Optional bundled instruments
```

## Development

Validate the package from the terminal:

```sh
swift build
```

This project currently sets Swift language mode to Swift 5 in `Package.swift`. That keeps AudioKit callback code practical while still building with modern Swift toolchains. A later hardening pass can move the mutable audio/UI state behind explicit actor boundaries.

AudioKit buffer length is set to `.short` before the engine starts for lower live MIDI latency.

## Roadmap

See [docs/PRD.md](docs/PRD.md) for the product requirements, current scope, and planned milestones.
