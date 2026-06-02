# Product Requirements Document: MiniLab Particle DJ

## Overview

MiniLab Particle DJ is a native macOS app that turns an Arturia MiniLab Mk2 into a small live performance workstation. The product combines a MIDI-controlled sampler rig, automatic harmony, instrument switching, and an audio-reactive visualizer so a single performer can play layered synth/DJ-style sets without a DAW.

The current implementation is an MVP starter app built with SwiftUI and AudioKit 5. It is intended to prove the core live loop: connect controller, choose a layer, select instruments with pads, play keys, hear generated harmony, and see visuals react to the performance.

## Goals

- Provide a low-latency native macOS performance app for MiniLab Mk2 users.
- Keep audio, MIDI, harmony, and visualization fully on-device.
- Make common live controls available from the controller, not only the screen.
- Support free instrument libraries through SoundFont and DLS loading.
- Establish a clean architecture that can grow into a fuller mini-DAW/VJ tool.

## Non-Goals

- Cloud-based audio generation or remote inference.
- Full DAW editing, arrangement timeline, or clip launcher in the first version.
- Commercial SoundFont bundling without explicit license review.
- Deep controller editor support for every MiniLab mapping preset.
- Plugin hosting for VST/AU instruments in the MVP.

## Target Users

- Musicians with an Arturia MiniLab Mk2 who want a lightweight performance rig.
- Producers who want fast sketching without opening a full DAW.
- Live visual performers who want visuals tied directly to MIDI/audio energy.
- Beginners who want automatic harmony while learning keys and chord structure.

## Current MVP Scope

### Audio Engine

- One AudioKit `AudioEngine`.
- Four `AppleSampler` layers.
- One output `Mixer`.
- Built-in macOS DLS bank used for starter sounds.
- Runtime `.sf2` and `.dls` import into the current layer.
- Separate loop playback samplers preserve the instrument sound used when a phrase was captured.
- Dedicated drum sampler provides the built-in beat.

### MIDI Input

- AudioKit `MIDI` listens to Core MIDI inputs.
- MIDI note-on plays the selected layer.
- MIDI note-off stops the played note and generated harmony notes.
- Pad notes `36...51` on the configured pad channel select the shared performance instrument used by melody and harmony layers.
- Keyboard notes `36...51` remain playable melody notes and do not change instruments unless they arrive on the configured pad channel.
- CC messages `71`, `72`, `73`, and `74` control visual parameters.

### Harmony

- Tracks active notes per layer.
- Estimates key and chord context from active/recent melody notes.
- Generates diatonic harmony notes from scale degrees and detected chord tones.
- Routes harmony voices across the other sampler layers.
- Mirrors the selected instrument across layers by default so harmonies feel like one coherent played instrument.
- Supports harmony styles: off, close thirds, open fifths, full triad, and dreamy.
- Supports hardware-controlled voice count and spread.
- Supports screen-controlled key, scale, time signature, and harmony complexity.
- Can generate grid-aligned harmony motion from a single played note.

### Visualizer

- AudioKit `FFTTap` analyzes the mixed output.
- Bass, mid, and treble bands drive particle behavior.
- Note velocity adds transient visual energy.
- SwiftUI `Canvas` renders particles.
- Knobs control brightness, gravity, particle size, and trail feel.

### UI

- Main performance screen with full-window particle visualizer.
- Full-window visualizer-first performance screen.
- Compact HUD for audio/MIDI state, last MIDI event, current instrument, and detected harmony label.
- Compact rhythm controls for loop tempo, loop interval, and loop enablement.
- Key, scale, time-signature, drum, and harmony-complexity controls.
- Recent played-event log showing note, instrument, harmony mode, and rhythm.
- Particle-only visualizer without graph-style meters over the performance view.

## User Stories

- As a performer, I can connect my MiniLab Mk2 and immediately play a sound from the keys.
- As a performer, I can press a pad to switch the current layer's instrument.
- As a performer, I can select a different layer on screen and load a different instrument into it.
- As a performer, I can play a melody and hear automatic harmony on companion layers.
- As a performer, I can turn knobs and see the visualizer respond during playback.
- As a producer, I can import a free SoundFont and use it without modifying the code.
- As a developer, I can change controller note/CC mappings in one place.

## Functional Requirements

### Audio

- The app must start an AudioKit engine when the main window opens.
- The app must create four playable sampler layers.
- The app must route all layers to a shared mixer output.
- The app must load starter presets from a local DLS source.
- The app must accept user-selected `.sf2` and `.dls` files at runtime.

### MIDI

- The app must listen to Core MIDI input ports.
- The app must handle note-on and note-off events.
- The app must map MiniLab-style pad notes to instrument presets.
- The app must map selected CC messages to visual controls.
- The app must support an all-notes-off path from hardware controls.
- The app should tolerate unknown CC/program/aftertouch/system messages without failing.

### Harmony

- The app must generate harmony voices in real time from incoming note-on events.
- The app must keep generated notes within the valid MIDI note range.
- The app should prefer diatonic harmony based on detected major/minor context.
- The app should use recent note history and active notes to infer chord context.
- The app should support live harmony preset changes from MiniLab controls.
- The app should avoid blocking the MIDI callback with expensive analysis.

### Looping

- The app must collect notes released inside the current measure into a phrase buffer.
- The app must repeat captured phrase notes five times as one bar-aligned phrase.
- Each repeat must be quieter than the previous repeat.
- The app must fade repeats gradually enough that previous phrases remain audible while new instruments are selected.
- The app must preserve the captured instrument timbre for scheduled repeats even after the live instrument changes.
- The app must expose tempo and time-signature controls on screen.
- The app must quantize scheduled loop repeats to the selected measure grid.
- Panic/all-notes-off must cancel future scheduled loop repeats.

### Drums

- The app must provide a basic built-in drum beat.
- The app must expose a drum enable/disable control on screen.
- Drum timing must follow BPM and selected time signature.
- Drum patterns should differ for `4/4`, `3/4`, `6/8`, and `3/8`.
- Drum Kit must also be available as one of the selectable pad instruments.

### Visualization

- The app must analyze mixer output with FFT.
- The app must expose bass, mid, and treble energy to the UI.
- The app must render particles continuously while the app is open.
- The app must react to both audio energy and MIDI note velocity.
- The app should not draw graph-style meters over the particle performance view.

### UI

- The app must show active preset, app status, and last MIDI event without covering the visualizer.
- The app must keep the primary screen visualizer-first with no required mouse controls.
- The app should expose instrument selection through the MiniLab pads.
- The app should be usable at a desktop window size of at least `1120 x 720`.

## Non-Functional Requirements

- Audio and MIDI response should feel immediate for live playing.
- The app must run without cloud services.
- The app should build as a Swift package and open cleanly in Xcode.
- Visual rendering should remain smooth under normal particle counts.
- Feature code should stay separated by responsibility: audio/MIDI, harmony, instruments, UI, and visuals.

## Success Metrics

- The app builds successfully with `swift build`.
- A connected MiniLab Mk2 can trigger sound from the keyboard.
- All 16 pads can select visible starter presets.
- Holding pad 1 and pad 16 together stops active notes.
- Holding pad 13 and pressing pads 1-4 changes the current layer.
- Holding pad 14 and pressing pads 1-5 changes harmony mode.
- Imported `.sf2` or `.dls` files can be loaded into a layer.
- Particles respond to played audio and MIDI note velocity.
- No crash when receiving unsupported MIDI messages.

## Risks and Open Questions

- MiniLab pad note numbers can vary by user preset; mapping customization needs a UI.
- SoundFont licensing must be reviewed before bundling any third-party packs.
- `AppleSampler` behavior differs across SF2 files; some packs may need bank/program handling.
- Strict Swift concurrency hardening is deferred because AudioKit callbacks are currently compiled in Swift 5 language mode.
- Command-line build works, but full app runtime testing should be done in Xcode with actual MIDI hardware.

## Milestones

### M1: Hardware Validation

- Test with a real MiniLab Mk2.
- Confirm default pad notes and knob CC values.
- Add a MIDI monitor panel for discovering custom mappings.
- Confirm note-off behavior for generated harmony voices.
- Confirm pad 1 + pad 16 panic behavior on actual MiniLab hardware.

### M2: Instrument Workflow

- Add a persistent instrument library browser.
- Remember imported SoundFont locations with security-scoped bookmarks.
- Add per-layer volume, mute, solo, and octave shift.
- Add preset naming and save/load performance sessions.

### M3: Harmony Controls

- Add selectable harmony modes: off, triad, seventh, spread, bass support.
- Add key/scale lock.
- Add chord memory from pads.
- Add humanization for velocity and timing.

### M4: Performance FX

- Add filter, delay, reverb, compressor, and limiter.
- Map MiniLab knobs to audio effects as well as visuals.
- Add panic/all-notes-off and output level protection.

### M5: Visual System

- Add visual scenes and presets.
- Add fullscreen performance mode.
- Add beat/bass transient detection.
- Add Metal renderer if Canvas performance becomes a bottleneck.

## Implementation Notes

- Current app source lives in `Sources/MiniLabParticleDJ`.
- Audio and MIDI orchestration lives in `AudioManager.swift`.
- Harmony logic lives in `HarmonyEngine.swift`.
- Starter instruments live in `InstrumentLibrary.swift`.
- Visual rendering lives in `ParticleVisualizer.swift`.
- Main UI lives in `ContentView.swift`.
