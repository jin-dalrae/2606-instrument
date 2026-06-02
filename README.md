# MiniLab Particle DJ

A native macOS SwiftUI starter app that turns an Arturia MiniLab Mk2 into a small live synth/DJ station with layered samplers, pad-based instrument selection, rules-based auto harmony, and an audio-reactive particle visualizer.

## What is included

- AudioKit `AudioEngine`, `Mixer`, `AppleSampler`, `MIDI`, and `FFTTap` wiring.
- Four sampler layers routed into one mixer.
- MiniLab Mk2-style pad mapping for notes `36...51`.
- 25-key melody input with automatic third, fifth, and seventh harmony voices.
- Pad-driven instrument preset switching using the macOS built-in DLS sound bank.
- Runtime SF2/DLS import for free instrument libraries.
- SwiftUI `Canvas` particle visualizer driven by FFT bass, mid, treble, note velocity, and knobs.

## Running

Open the package in Xcode:

```sh
open Package.swift
```

Then select the `MiniLabParticleDJ` scheme and run it on macOS 14 or newer.

This workspace currently has Apple Command Line Tools selected instead of full Xcode, so command-line app building is not available here. Full validation should be done from Xcode.

## MiniLab Mk2 mapping

- Keys: play the current layer and generate harmony on the other layers.
- Pads `36...51`: select one of 16 built-in GM/DLS presets for the current layer.
- CC `74`: visual brightness.
- CC `71`: visual gravity.
- CC `73`: visual particle size.
- CC `72`: visual trail.

If your pads use different note numbers, change `padBaseNote` in `AudioManager.swift`.

## SoundFonts

The app can import `.sf2` or `.dls` files at runtime with the folder button in the UI. For bundled starter packs, place files under `Resources/SoundFonts` and load them from the app bundle in `InstrumentLibrary`.
